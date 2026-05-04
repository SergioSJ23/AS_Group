# Como Testar o Spike — SSO com Keycloak (ADR-001)

## Pré-requisitos

- Docker e Docker Compose instalados
- Portas 8080, 8081, 8082 livres no host
- `localtest.me` não precisa de configuração — resolve sempre para 127.0.0.1

---

## Fluxo de cada sessão

O spike foi desenhado para ser completamente limpo em cada sessão: cada `up --build` começa
do zero, o wizard corre sempre, e `down -v` destrói tudo. Não há estado persistente entre
sessões.

```
docker compose up --build   →  wizard  →  configurar plugin  →  testar SSO
docker compose down -v      →  tudo apagado, pronto para a próxima sessão
```

---

## 1. Arranque

A partir da raiz do repositório:

```bash
docker compose -f spike/docker-compose.spike.yml up --build
```

O `--build` compila o nopCommerce incluindo o plugin Keycloak (primeira vez ~5 min,
seguintes usam cache Docker).

Aguardar até ver nos logs que os containers do nopCommerce estão a servir pedidos
(`Application started`).

---

## 2. Wizard de instalação do nopCommerce

O wizard corre sempre porque não há `appsettings.json` persistido. Abrir em dois separadores:

### BU1 — HomeStyle

1. Aceder a `http://bu1.localtest.me:8081`
2. Preencher:
   - **Admin e-mail:** `admin@bu1.com`
   - **Admin password:** `Admin123!`
   - **Database:** PostgreSQL
   - **Server:** `db_bu1`
   - **Database name:** `nop_bu1`
   - **Username:** `nop`
   - **Password:** `noppassword`
3. Submeter — aguardar restart automático (~2 min)
4. Quando o container parar, executar:
   ```bash
   docker compose -f spike/docker-compose.spike.yml start nop_bu1
   ```

### BU2 — WorkSpace

1. Aceder a `http://bu2.localtest.me:8082`
2. Mesmas opções, excepto:
   - **Server:** `db_bu2`
   - **Database name:** `nop_bu2`
   - **Admin e-mail:** `admin@bu2.com`
3. Submeter — aguardar restart automático
4. Quando o container parar, executar:
   ```bash
   docker compose -f spike/docker-compose.spike.yml start nop_bu2
   ```

---

## 3. Configurar o plugin Keycloak em cada BU

### BU1

1. `http://bu1.localtest.me:8081/login` → entrar com `admin@bu1.com` / `Admin123!`
2. **Admin → Configuration → External Authentication Methods**
3. Editar **Keycloak** → activar → **Configure**:
   - **Authority:** `http://keycloak.localtest.me:8080/realms/northstar`
   - **Client ID:** `bu1-nopcommerce`
   - **Client Secret:** `bu1-secret`
4. Guardar

### BU2

1. `http://bu2.localtest.me:8082/login` → entrar com `admin@bu2.com` / `Admin123!`
2. Mesmo processo, com:
   - **Client ID:** `bu2-nopcommerce`
   - **Client Secret:** `bu2-secret`
3. Guardar

---

## 4. Teste de SSO — critérios de aceitação

### AC1 — Login via Keycloak na BU1

1. Abrir `http://bu1.localtest.me:8081/login` em modo **privado/incógnito**
2. Clicar no botão **Keycloak**
3. Fazer login como `alice@example.com` / `alice123`
4. **Resultado esperado:** redireccionado de volta para BU1 autenticado como alice

### AC2 — SSO na BU2 sem nova autenticação

1. Na **mesma janela** (não abrir nova incógnito), aceder a `http://bu2.localtest.me:8082/login`
2. Clicar em **Keycloak**
3. **Resultado esperado:** sem pedir credenciais — autenticado automaticamente como alice

> Este é o teste crítico do ADR-001: uma sessão Keycloak partilhada entre duas BUs.

### AC3 — Registo na base de dados

```bash
# BU1
docker exec spike-db_bu1-1 psql -U nop -d nop_bu1 -c \
  "SELECT ExternalIdentifier, Email FROM \"ExternalAuthenticationRecord\";"

# BU2
docker exec spike-db_bu2-1 psql -U nop -d nop_bu2 -c \
  "SELECT ExternalIdentifier, Email FROM \"ExternalAuthenticationRecord\";"
```

**Resultado esperado:** uma linha em cada BD com o `sub` claim do Keycloak (UUID) e `alice@example.com`.

---

## 5. Paragem e limpeza

```bash
docker compose -f spike/docker-compose.spike.yml down -v
```

Remove containers, rede e volumes de BD. Na próxima sessão recomeça do passo 1.

---

## Credenciais de referência

| Serviço | URL | Utilizador | Password |
|---|---|---|---|
| Keycloak Admin | `http://keycloak.localtest.me:8080` | `admin` | `admin` |
| Utilizador de teste | — | `alice@example.com` | `alice123` |
| nopCommerce BU1 | `http://bu1.localtest.me:8081` | `admin@bu1.com` | `Admin123!` |
| nopCommerce BU2 | `http://bu2.localtest.me:8082` | `admin@bu2.com` | `Admin123!` |

---

## Troubleshooting

**`keycloak.localtest.me` não acessível a partir do container nopCommerce**
O `extra_hosts: host-gateway` em `docker-compose.spike.yml` trata disto. Se falhar:
```bash
docker run --rm --add-host=test:host-gateway alpine ping -c1 test
```

**BU2 continua a pedir login (AC2 falha)**
O browser tem de enviar o cookie de sessão do Keycloak. Certificar que está a usar a
mesma janela de browser (não uma nova janela incógnito) para ambas as BUs.

**nopCommerce mostra 500 após o wizard**
```bash
docker compose -f spike/docker-compose.spike.yml restart nop_bu1
```
