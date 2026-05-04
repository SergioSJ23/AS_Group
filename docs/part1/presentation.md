---
marp: true
theme: default
paginate: true
style: |
  section {
    font-family: 'Segoe UI', sans-serif;
    font-size: 1.1rem;
  }
  h1 { color: #1a1a2e; font-size: 2rem; }
  h2 { color: #16213e; border-bottom: 3px solid #e94560; padding-bottom: 6px; }
  h3 { color: #0f3460; }
  table { font-size: 0.85rem; width: 100%; }
  th { background: #1a1a2e; color: white; }
  code { background: #f0f0f0; padding: 2px 6px; border-radius: 4px; font-size: 0.85rem; }
  .columns { display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; }
  blockquote { border-left: 4px solid #e94560; padding-left: 1rem; color: #555; }
---

<!-- _paginate: false -->
<!-- _class: lead -->

# Northstar Living Group
## Federated Commerce Platform
### Software Architecture — Part 1

**Grupo:** AS Group
**Data:** Maio 2026

---

## Agenda

1. Cenário e contexto de negócio
2. Estado actual do nopCommerce
3. Pressure points identificados
4. Quality Attribute Scenarios
5. Framework de design — ADD
6. Arquitectura alvo (5 iterações)
7. ADRs — decisões tomadas
8. Plano de risco
9. Spike de viabilidade — Keycloak SSO

---

## 1. Cenário — Northstar Living Group

> Holding de retalho que cresceu por aquisição. Várias marcas especialistas, cada uma com catálogo, preços e operações próprias.

**O desafio central:**

| Força centralizadora | Força descentralizadora |
|---|---|
| Identidade única no grupo, SSO | Preços e catálogo por BU |
| Plataforma partilhada (custo) | Deployability independente |
| Insights de grupo | Sem propagação de falhas entre BUs |

**Porquê nopCommerce?**
Sistema *store-aware mas não store-enforced* — tem conceito de multi-store mas o isolamento é opt-in. Cria pressão arquitectural real.

**BUs no scope:** BU1 — HomeStyle · BU2 — WorkSpace

---

## 2. Arquitectura actual — nopCommerce

**Arquitectura em cebola** sobre C# / ASP.NET Core. Dependências só para dentro.

```
Nop.Core  ←  Nop.Data  ←  Nop.Services  ←  Nop.Web.Framework  ←  Nop.Web
                                                                      ↑
                                                                   Plugins/
```

**Multi-store built-in:**
- Cada store tem URL, tema e settings próprios
- Catálogo partilhado por defeito — isolamento via `StoreMapping` é **opt-in**
- `Setting.StoreId = 0` é global; `> 0` é store-specific
- Sem conceito de grupo de stores, hierarquia ou parent-child

---

## 3. Pressure Points identificados (P1–P7)

| # | Área | Problema |
|---|---|---|
| **P1** | Preços | `Product.Price` é global — sem dimensão de store |
| **P2** | Identidade | `Customer.Email` global, `CustomerRole` sem `StoreId` |
| **P3** | Inventário | `ProductWarehouseInventory` sem `StoreId` — warehouses partilhados |
| **P4** | Coordenação | `IEventPublisher` in-process only, sem broker, sem durabilidade |
| **P5** | Settings | Global fallback sem governança por BU |
| **P6** | Catálogo | `IgnoreStoreLimitations` desactiva todo o isolamento com um toggle |
| **P7** | ACL | Role-scoped only — sem store scope nas regras de acesso |

**Mais críticos para o cenário:** P2 (identidade), P3 (inventário), P4 (coordenação)

---

## 4. Quality Attribute Scenarios

| ID | Atributo | Driver principal |
|---|---|---|
| **QA1** | Availability | ERP de uma BU falha → outras BUs não são afectadas |
| **QA2** | Modifiability | Pricing de BU1 muda → BU2 completamente inalterada |
| **QA3** | Security / Interop | SSO entre BUs — sem re-autenticação, roles por BU |
| **QA4** | Reliability | Meilisearch cai → fallback automático para DB; recovery sem intervenção |
| **QA5** | Consistency | Order de BU2 chega ao CRM em ≤30s; survives consumer outage 24h |

---

## QA3 — Federated Identity (detalhe)

> Cliente autenticado na BU1 navega para BU2 — não deve ser pedida nova autenticação.

| Parte | Descrição |
|---|---|
| **Source** | Cliente autenticado via SSO na BU1 |
| **Stimulus** | Acede ao URL da BU2 |
| **Artifact** | Sessão de autenticação, roles por BU |
| **Response** | Reconhecido na BU2 sem login; roles da BU2 aplicados; roles da BU1 não visíveis |
| **Measure** | Sem login prompt; transição < 2s; zero role bleed-through |

**Trace:** P2 (identidade global) → BC1 (Group Identity) → ADR-001

---

## 5. Framework — ADD 3.0

**Attribute-Driven Design** — decomposição iterativa guiada por quality attributes.

```
1. Seleccionar elemento a decompor
2. Identificar drivers (QA scenarios + constraints)
3. Escolher padrão/táctica que responde aos drivers
4. Instanciar e alocar responsabilidades
5. Verificar que satisfaz os drivers
6. Repetir para sub-elementos
```

**Porquê ADD para este caso:**
- Temos QA scenarios explícitos e mensuráveis
- O nopCommerce impõe constraints claras (não substituir o core)
- As decisões têm trade-offs reais — ADD força a explicitar o raciocínio

---

## 6. Arquitectura Alvo — Visão Geral

Cinco iterações ADD, cada uma endereça um driver prioritário:

| Iteração | Driver | Decisão principal |
|---|---|---|
| **1** | QA3 — Identity | Keycloak como IdP externo (ADR-001) |
| **2** | QA1 — Fault isolation | ERP por BU + circuit breaker (ADR-003) |
| **3** | QA5 — Async coordination | RabbitMQ como event bus (ADR-002) |
| **4** | QA4 — Search reliability | Meilisearch + DB fallback (ADR-004) |
| **5** | QA2 — BU autonomy | StoreMapping obrigatório (ADR-005) |

---

## Arquitectura Alvo — Diagrama

```
┌─────────────────────────────────────────────────────────┐
│                   Keycloak (BC1)                        │
│              Group Identity Provider                    │
└──────────────┬──────────────────────┬───────────────────┘
               │ OIDC                 │ OIDC
       ┌───────▼──────┐       ┌───────▼──────┐
       │  nopCommerce │       │  nopCommerce │
       │     BU1      │       │     BU2      │
       │  (HomeStyle) │       │  (WorkSpace) │
       └──────┬───────┘       └───────┬──────┘
              │                       │
       ┌──────▼───────────────────────▼──────┐
       │           RabbitMQ (BC2)            │
       │         Cross-BU Event Bus          │
       └──────┬───────────────────────┬──────┘
              │                       │
       ┌──────▼──────┐       ┌────────▼────────┐
       │ ERPNext BU1 │       │   Odoo BU2      │
       │  (circuit   │       │  (circuit       │
       │  breaker)   │       │   breaker)      │
       └─────────────┘       └─────────────────┘
```

---

## 7. ADRs — Decisões de Arquitectura

| ADR | Decisão | Driver |
|---|---|---|
| **ADR-001** | Keycloak como IdP OIDC partilhado | QA3 |
| **ADR-002** | RabbitMQ como event bus cross-BU | QA5 |
| **ADR-003** | ERP por BU com circuit breaker | QA1 |
| **ADR-004** | Meilisearch com fallback para DB | QA4 |
| **ADR-005** | StoreMapping obrigatório (mandatory) | QA2, P6 |

---

## ADR-001 — Keycloak como IdP (detalhe)

**Problema:** `Customer.Email` global, `CustomerRole` sem scope de BU. Não há SSO.

**Decisão:** Keycloak como IdP externo; cada BU é um OIDC Relying Party via plugin `Nop.Plugin.ExternalAuth.Keycloak` que implementa `IExternalAuthenticationMethod`.

- Fluxo: Authorization Code + PKCE
- Claims de grupo viajam no JWT; roles de BU ficam locais no nopCommerce
- Ligação via `sub` claim do Keycloak → `ExternalAuthenticationRecord`

**Trade-off aceite:** Keycloak torna-se dependency de grupo. Mitigado por HA pair e cookie-session para sessões já activas.

**Alternativas rejeitadas:** sync de clientes via eventos (consistência eventual na identidade é problemático); Azure AD B2C / Auth0 (vendor lock-in); SAML (protocolo pesado).

---

## ADR-002 — RabbitMQ Event Bus

**Problema:** `IEventPublisher` do nopCommerce é in-process, sem durabilidade, sem broker.

**Decisão:** RabbitMQ como broker externo. Exchange por tipo de evento; fila durável por consumer.

- Transactional outbox: evento escrito na mesma TX que a order
- Consumer idempotente: chave `(aggregate_id, version)`
- Relay processa o outbox e publica no RabbitMQ

**Trade-off:** Complexidade operacional. Justificado pelo requisito de 24h de durabilidade (QA5).

---

## ADR-003 · ADR-004 · ADR-005

**ADR-003 — ERP por BU com Circuit Breaker**
Cada BU tem ERP próprio (ERPNext / Odoo). ACL entre nopCommerce e ERP. Circuit breaker com degraded-but-open mode: stock em cache até 5 min de outage.

**ADR-004 — Meilisearch + DB Fallback**
Search index partilhado. Fallback automático para query directa à DB em ≤3s de detecção de falha. Resync automático após recovery.

**ADR-005 — StoreMapping Obrigatório**
Remove o toggle `IgnoreStoreLimitations` da admin UI. Pinado a `false` no startup. Qualquer produto novo exige mapeamento explícito de store antes de ser visível.

---

## 8. Plano de Risco — Riscos Principais (score ≥ 6)

| ID | Risco | P | I | Score |
|---|---|---|---|---|
| R1 | Keycloak SPOF de login para todo o grupo | 2 | 3 | **6** |
| R2 | Bug no outbox → eventos duplicados ou perdidos | 2 | 3 | **6** |
| R4 | Migração de clientes para Keycloak perde/duplica contas | 2 | 3 | **6** |
| R10 | Role mapping entre BUs deriva → role bleed-through | 2 | 3 | **6** |

**Mitigações principais:**
- R1 → Keycloak HA pair; sessão cookie mantida até expirar
- R2 → Outbox transaccional; consumer idempotente com chave composta
- R4 → Link by email no primeiro login pós-migração; ferramenta de reconciliação
- R10 → Tabela de mapping num único source-of-truth em git; carregada no startup

---

## 9. Spike de Viabilidade — ADR-001

**Questão a responder:** O nopCommerce consegue usar o Keycloak como IdP OIDC partilhado com SSO real entre BUs?

**O que foi construído:**
- Plugin `Nop.Plugin.ExternalAuth.Keycloak` (implementa `IExternalAuthenticationMethod`)
- Docker Compose: Keycloak 26 + 2× PostgreSQL + 2× nopCommerce
- Realm `northstar` com clients `bu1-nopcommerce` e `bu2-nopcommerce`
- Utilizador de teste: `alice@example.com`

---

## Spike — Resultados

| Critério | Resultado |
|---|---|
| Login via Keycloak na BU1 | ✅ Redireccionamento OIDC funciona |
| SSO na BU2 sem nova autenticação | ✅ Keycloak não pede credenciais |
| Registo em `ExternalAuthenticationRecord` | ✅ `sub` claim ligado ao Customer |

**Problemas encontrados e resolvidos:**
- SDK `Microsoft.NET.Sdk.Web` necessário para pacotes inbox do ASP.NET Core
- `_ViewImports.cshtml` incompleto causava falha de compilação Razor em runtime
- `ResponseMode = "query"` necessário — o `form_post` padrão falha com `SameSite=Lax`

**Conclusão:** ADR-001 é viável. O plug-in slot `IExternalAuthenticationMethod` do nopCommerce suporta OIDC de forma limpa.

---

## Resumo Final

| Área | Decisão |
|---|---|
| **Identidade** | Keycloak OIDC — SSO entre BUs ✅ provado em spike |
| **Coordenação** | RabbitMQ + transactional outbox |
| **Fault isolation** | ERP por BU + circuit breaker |
| **Search** | Meilisearch + DB fallback automático |
| **Isolamento** | StoreMapping obrigatório |

> O cenário de federação é arquitecturalmente viável com o nopCommerce como core. As decisões são rastreáveis aos quality attribute scenarios e fecham os pressure points identificados no estado actual.

---

<!-- _paginate: false -->
<!-- _class: lead -->

# Obrigado

**Repositório:** `AS_Group`
**Spike:** `spike/docker-compose.spike.yml`
**Docs:** `docs/part1/`
