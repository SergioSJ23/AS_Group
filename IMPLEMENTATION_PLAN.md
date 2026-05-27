# Part 2 — Implementation Plan

**Scenario A — Federated Commerce After Acquisitions**
**Deadline: 02–03 June 2026**

---

## Foundation: what already exists

| Already built | Status |
|---|---|
| `Nop.Plugin.ExternalAuth.Keycloak` | Complete |
| `spike/docker-compose.spike.yml` | 2 nopCommerce + 2 Postgres + Keycloak |
| `spike/keycloak/realm-northstar.json` | Keycloak realm com 2 OIDC clients |
| Part 1 report + 5 ADRs | Complete (status: Proposed) |

O spike é o scaffold. Cada fase abaixo estende-o.

---

## Phase 0 — Full infrastructure compose

**Goal:** todos os 8 subsistemas correm com `docker compose up`  
**Output:** `docker-compose.yml` na raiz do repo (substitui o spike compose)

Adicionar ao spike compose existente:

```
rabbitmq    — management:3.13-alpine, ports 5672 / 15672
meilisearch — getmeili/meilisearch:v1.7, port 7700
espocrm     — espocrm/espocrm:latest + espocrm_db (MariaDB)
erp_bu1     — minimal ASP.NET image, port 9001
erp_bu2     — minimal ASP.NET image, port 9002
```

Os blocos de environment de BU1 e BU2 recebem novas variáveis: `RABBITMQ_URI`, `MEILISEARCH_URI`, `ERP_URI`.

**Verificação:** `docker compose ps` mostra todos os 10 containers healthy.

---

## Phase 1 — ADR-001: Per-BU process and database isolation

**Goal:** provar que uma falha na DB de BU1 não afeta BU2  
**Work:** só configuração, sem alterações de código

- O spike compose já tem `db_bu1` / `db_bu2` com volumes separados.
- Garantir que nenhuma `ConnectionStrings` env var é partilhada entre `nop_bu1` e `nop_bu2`.
- Adicionar script de health-check: `scripts/test-isolation.sh` — para `db_bu1`, faz GET a BU2 `/`, espera HTTP 200.

**Ficheiros tocados:**
- `docker-compose.yml` (estende spike)
- `scripts/test-isolation.sh` (novo)

**Verificação:** homepage de BU2 retorna 200 enquanto a DB de BU1 está em baixo.

---

## Phase 2 — ADR-002: Keycloak SSO (já spiked)

**Goal:** cliente faz login em BU1, navega para BU2, sem prompt de re-autenticação

**Work:** mínimo — o plugin já existe. O que é necessário:

1. Verificar que ambas as instâncias têm o plugin Keycloak instalado e configurado via env vars.
2. Confirmar que `realm-northstar.json` tem os clients `bu1-nopcommerce` e `bu2-nopcommerce` com redirect URIs corretos.
3. Corrigir o problema conhecido do spike: `response_mode=query` tem de estar definido (SameSite cookie no cross-site POST).
4. Adicionar `scripts/test-sso.sh` que usa `curl` para verificar o redirect silencioso em BU2 após login em BU1.

**Ficheiros tocados:**
- `docker-compose.yml` (adicionar env: `KEYCLOAK_CLIENT_ID`, `KEYCLOAK_CLIENT_SECRET`, `KEYCLOAK_AUTHORITY` por BU)
- `spike/keycloak/realm-northstar.json` (verificar redirect URIs)
- `scripts/test-sso.sh` (novo)

**Verificação:** sessão única no browser — login em BU1, navegar para URL de BU2 → sem prompt de credenciais, role específica de BU2 aplicada.

---

## Phase 3 — ADR-003: Transactional outbox → RabbitMQ → CRM

**Goal:** order colocada em BU2 chega ao EspoCRM em menos de 30s; sobrevive a downtime do CRM durante 24h sem perda de dados

**Novo plugin:** `src/Plugins/Nop.Plugin.Misc.OutboxRelay/`

```
Nop.Plugin.Misc.OutboxRelay/
  Domain/
    OutboxMessage.cs            — Id, BuId, EventType, Payload (json), CreatedAt, PublishedAt?
  Data/
    OutboxMessageBuilder.cs     — FluentMigrator entity builder (adiciona tabela outbox à DB do BU)
    SchemaMigration.cs          — migration 20250601 000000
  Services/
    IOutboxWriter.cs            — Task WriteAsync(string eventType, object payload)
    OutboxWriter.cs             — insere OutboxMessage na mesma transação DB
    OutboxRelayService.cs       — BackgroundService: polling de rows não publicadas,
                                   publica no RabbitMQ, marca como publicadas
    RabbitMqPublisher.cs        — wraps IConnection, topic exchange "northstar.events"
  Consumers/
    OrderPlacedConsumer.cs      — IEventConsumer<OrderPlacedEvent>, chama IOutboxWriter
  OutboxRelayPlugin.cs          — BasePlugin + IMiscPlugin, regista serviços
  plugin.json
  Nop.Plugin.Misc.OutboxRelay.csproj
```

**Topologia RabbitMQ:**
- Exchange: `northstar.events` (topic, durable)
- Routing key: `{buId}.order.placed`
- Queue: `northstar.crm.orders` (durable, dead-letter → `northstar.dlx`)

**EspoCRM consumer:** `src/Workers/EspoCrmConsumer/`
- Standalone .NET `BackgroundService`
- Subscreve `northstar.crm.orders`
- Chama a REST API do EspoCRM para upsert do histórico de contacto
- Idempotente: keyed em `(OrderId, version)` — se já processado, ack e skip

**Propriedade de correção chave:** `OrderPlacedConsumer` usa `IRepository<OutboxMessage>` dentro do mesmo scope de transação `IDbContext` que o insert da order → dual-write hazard eliminado por construção.

**Verificação:**
- Colocar order em BU2 → verificar que tabela `outbox` tem uma row → relay publica → contacto EspoCRM atualizado em 30s.
- Parar container EspoCRM → colocar 5 orders → reiniciar → todas as 5 processadas sem duplicados.

---

## Phase 4 — ADR-004: BU-local ERP com ACL + circuit breaker

**Goal:** ERP de BU2 falha → BU2 mostra stock em cache + banner "stock to be confirmed" → BU1 não é afetado → ERP recupera → operação normal retoma automaticamente

**Novo serviço ERP stub:** `src/Workers/ErpStub/`
- Minimal API ASP.NET
- `GET /stock/{sku}` → retorna `{ sku, quantity, warehouseId }` (dados sintéticos)
- `POST /admin/break` → faz o serviço retornar 503 em todas as chamadas `/stock`
- `POST /admin/recover` → restaura respostas normais
- Mesma imagem usada para containers `erp_bu1` e `erp_bu2`

**Novo plugin:** `src/Plugins/Nop.Plugin.Misc.ErpIntegration/`

```
Nop.Plugin.Misc.ErpIntegration/
  Domain/
    StockResult.cs              — { int Quantity, bool IsStale, string Source }
  Services/
    IErpStockService.cs         — Task<StockResult> GetStockAsync(string sku)
    ErpStockService.cs          — HTTP call ao ERP_URI, wrapped por Polly + cache
    CircuitBreakerPolicy.cs     — AsyncCircuitBreakerPolicy:
                                   5 falhas → OPEN, 30s cooldown, probe half-open
    StockCacheService.cs        — IStaticCacheManager, key "erp.stock.{sku}", TTL 5 min
  Consumers/
    ProductPageEventConsumer.cs — IEventConsumer<ProductDetailsModelPreparedEvent>,
                                   enriquece modelo com stock live/cached
  ErpIntegrationPlugin.cs
  plugin.json
  Nop.Plugin.Misc.ErpIntegration.csproj
```

**Fluxo de estados do circuit breaker:**

```
CLOSED    →  (5 falhas consecutivas)  →  OPEN
OPEN      →  (30s cooldown)           →  HALF-OPEN
HALF-OPEN →  (probe OK)               →  CLOSED
HALF-OPEN →  (probe falha)            →  OPEN
```

Quando OPEN: `GetStockAsync` lança `BrokenCircuitException`, capturada por `ErpStockService` que retorna `StockResult { Quantity = cached, IsStale = true }`.

**Scripts de verificação:**
```
scripts/test-erp-failure.sh   — POST /admin/break em erp_bu2, verifica banner em página
                                 de produto de BU2, verifica ausência de banner em BU1
scripts/test-erp-recovery.sh  — POST /admin/recover, aguarda probe do circuit, verifica
                                 que banner desaparece
```

---

## Phase 5 — ADR-005: Meilisearch federated search com DB fallback

**Goal:** ambos os storefronts pesquisam via Meilisearch; Meilisearch falha → fallback para DB search; recupera automaticamente

**Novo plugin:** `src/Plugins/Nop.Plugin.Search.Meilisearch/`

Implementa `ISearchProvider` (mesmo contrato que o Lucene plugin):
```csharp
Task<List<int>> SearchProductsAsync(string keywords, bool isLocalized)
```

```
Nop.Plugin.Search.Meilisearch/
  Services/
    MeilisearchClient.cs        — wraps Meilisearch .NET SDK, index "products"
    MeilisearchIndexer.cs       — bulk index + upsert de documento individual
    FallbackSearchService.cs    — estratégia: tenta Meilisearch (timeout 1.5s),
                                   em BrokenCircuit/timeout → DB search via ProductService
    MeilisearchHealthProbe.cs   — BackgroundService: a cada 30s faz probe a /health,
                                   sinaliza open/close do circuit breaker
  Consumers/
    ProductSavedConsumer.cs     — IEventConsumer<EntityInsertedEvent<Product>>
                                   + IEventConsumer<EntityUpdatedEvent<Product>>
                                   → upsert de documento no Meilisearch
  Infrastructure/
    SearchResultBannerFilter.cs — IActionFilter, define ViewData["SearchFallback"]=true
                                   quando resultado veio do DB fallback
  MeilisearchSearchProvider.cs  — implementação de ISearchProvider, delega para FallbackSearchService
  plugin.json
  Nop.Plugin.Search.Meilisearch.csproj
```

**Formato do documento no índice:**
```json
{
  "id": "bu1-42",
  "productId": 42,
  "buId": "bu1",
  "name": "...",
  "description": "...",
  "sku": "..."
}
```

Pesquisa cross-BU: ambos os BUs indexam no mesmo Meilisearch, com `buId` como atributo filtrável. Em cada storefront, os resultados são filtrados pelo `buId` desse BU.

População do índice no arranque: `MeilisearchSearchProvider.InstallAsync()` faz bulk-index de todos os produtos existentes.

**Scripts de verificação:**
```
scripts/test-search-fallback.sh  — docker stop meilisearch, pesquisa em BU1, espera
                                    resultados (DB) + banner "limited results"
scripts/test-search-recovery.sh  — docker start meilisearch, aguarda 35s probe,
                                    pesquisa novamente, espera resultados completos sem banner
```

---

## Phase 6 — Evidence pack + docs atualizados

**Goal:** prova auditável de que cada QA scenario está satisfeito

**Diretório:** `docs/part2/evidence/`

| Ficheiro | Conteúdo |
|---|---|
| `01-sso-flow.md` | Transcrição + curl trace dos Flows 1 e 2 (SSO em BU1 e BU2) |
| `02-erp-circuit-breaker.md` | Métricas Polly, timestamps, transições de estado do breaker |
| `03-outbox-durability.md` | Screenshots do RabbitMQ management UI, medições de consumer lag |
| `04-search-fallback.md` | Comparação de tempos: Meilisearch (≤200ms) vs DB (≤5s) |
| `05-bu-isolation.md` | Trace `docker stop db_bu1` → BU2 continua 200 OK |
| `known-limitations.md` | Política de reconciliação para orders pending-fulfilment; bound do consumer lag do CRM |

**ADRs atualizados:** todos os 5 passam de `Status: Proposed` → `Status: Accepted`, com notas de implementação.

**Relatório atualizado:** `docs/part2/report/` — curto, focado, cobre o que mudou do design do Part 1 para a implementação final, com screenshots do demo a correr.

**Instruções de setup:** `docs/part2/SETUP.md` — comando único `docker compose up --build`, pré-requisitos, output esperado, script de walkthrough do demo.

---

## Ordem de dependências e riscos

```
Phase 0 ──► Phase 1 ──► Phase 2 ──► Phase 3
                                         │
                                         ▼
                         Phase 4 ──► Phase 5 ──► Phase 6
```

Phase 3 tem de vir antes da Phase 5 porque o pipeline de re-indexação do Meilisearch reutiliza o broker RabbitMQ do ADR-003 (product-changed events fluem pelo mesmo exchange).

**Itens de maior risco:**

1. **ADR-003 correção do outbox** — `IEventConsumer<OrderPlacedEvent>` tem de escrever no outbox na mesma transação DB que o insert da order. nopCommerce usa `IDbContext` como unit of work; é necessário verificar que o consumer dispara dentro desse scope, e não após o commit.

2. **ADR-004 `ProductDetailsModelPreparedEvent`** — confirmar que este evento dispara com uma referência mutável ao modelo. Se disparar pós-render, a abordagem do banner muda para injeção via middleware no response body.

3. **`ISearchProvider` constraint de plugin único** — `SearchPluginManager` carrega apenas um provider ativo por system name. O plugin Meilisearch tem de estar definido como `ActiveSearchProviderSystemName` nas settings do nopCommerce no arranque.

---

## Ordem de trabalho sugerida

| Sessão | Trabalho |
|---|---|
| 1 | Phase 0 + Phase 1 — compose completo a correr, isolation test a passar |
| 2 | Phase 2 — SSO end-to-end verificado |
| 3–4 | Phase 3 — outbox + relay + CRM consumer |
| 5–6 | Phase 4 — ERP stub + circuit breaker + scripts de demo |
| 7–8 | Phase 5 — Meilisearch plugin + fallback + scripts de demo |
| 9 | Phase 6 — evidence pack + docs atualizados + relatório |
