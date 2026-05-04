# Como Testar o Spike — SSO com Keycloak (ADR-001)

## Pré-requisitos

- Docker e Docker Compose instalados
- Portas 8080, 8081, 8082 livres no host
- `localtest.me` não precisa de configuração — resolve sempre para 127.0.0.1

---

## 1. Build e arranque

```bash
cd spike
docker compose -f docker-compose.spike.yml up --build
```

Aguardar até os três serviços estarem healthy. O Keycloak demora ~30s.

> **Nota:** Na primeira vez que os containers arrancam sem volumes de BD existentes,
> é necessário fazer o passo 2. Se os volumes já existem (re-arranque), saltar para o passo 3.

---

## 2. Wizard de instalação do nopCommerce (apenas na primeira vez)

Abrir em dois separadores de browser diferentes:

### BU1 — HomeStyle
1. Aceder a `http://bu1.localtest.me:8081`
2. Preencher o wizard:
   - **Admin e-mail:** qualquer (ex: `admin@bu1.com`)
   - **Admin password:** qualquer (ex: `Admin123!`)
   - **Database:** PostgreSQL
   - **Server:** `db_bu1`
   - **Database name:** `nop_bu1`
   - **Username:** `nop`
   - **Password:** `noppassword`
3. Submeter e aguardar o restart automático (~2 min)

### BU2 — WorkSpace
1. Aceder a `http://bu2.localtest.me:8082`
2. Mesmas opções mas:
   - **Server:** `db_bu2`
   - **Database name:** `nop_bu2`
3. Submeter e aguardar

---

## 3. Configurar o plugin Keycloak em cada BU

### BU1
1. Aceder a `http://bu1.localtest.me:8081/login` com as credenciais de admin
2. Ir a **Admin → Configuration → External Authentication**
3. Activar o plugin **Keycloak** (clicar em Edit → Active)
4. Clicar em **Configure** e preencher:
   - **Authority:** `http://keycloak.localtest.me:8080/realms/northstar`
   - **Client ID:** `bu1-nopcommerce`
   - **Client Secret:** `bu1-secret`
5. Guardar

### BU2
1. Aceder a `http://bu2.localtest.me:8082/login` com as credenciais de admin
2. Mesmo processo, com:
   - **Authority:** `http://keycloak.localtest.me:8080/realms/northstar`
   - **Client ID:** `bu2-nopcommerce`
   - **Client Secret:** `bu2-secret`
3. Guardar

---

## 4. Teste de SSO — fluxo principal

### AC1 — Login via Keycloak na BU1

1. Abrir `http://bu1.localtest.me:8081/login` em modo **privado/incógnito**
2. Clicar no botão **Keycloak** (ou equivalente de external auth)
3. Ser redirecionado para `http://keycloak.localtest.me:8080`
4. Fazer login com:
   - **Email:** `alice@example.com`
   - **Password:** `alice123`
5. **Resultado esperado:** redireccionado de volta para BU1 e autenticado como alice

### AC2 — SSO na BU2 sem nova autenticação

1. Na **mesma janela de browser** (não incógnito novo), aceder a `http://bu2.localtest.me:8082/login`
2. Clicar em **Keycloak**
3. **Resultado esperado:** sem pedir credenciais — login automático e autenticado como alice na BU2

> Este é o teste crítico do ADR-001: uma só sessão Keycloak serve ambas as BUs.

### AC3 — Registo na base de dados

Verificar que o nopCommerce criou os registos de autenticação externa:

```bash
# BU1
docker exec spike-db_bu1-1 psql -U nop -d nop_bu1 -c \
  "SELECT ExternalIdentifier, Email FROM ExternalAuthenticationRecord;"

# BU2
docker exec spike-db_bu2-1 psql -U nop -d nop_bu2 -c \
  "SELECT ExternalIdentifier, Email FROM ExternalAuthenticationRecord;"
```

**Resultado esperado:** linha com o `sub` claim do Keycloak (UUID) e `alice@example.com` em ambas as BDs.

---

## 5. Paragem

```bash
docker compose -f spike/docker-compose.spike.yml down
```

Os volumes de BD persistem. Para destruir tudo incluindo dados:

```bash
docker compose -f spike/docker-compose.spike.yml down -v
```

---

## Credenciais de referência

| Serviço | URL | Utilizador | Password |
|---|---|---|---|
| Keycloak Admin | `http://keycloak.localtest.me:8080` | `admin` | `admin` |
| Utilizador de teste | — | `alice@example.com` | `alice123` |
| nopCommerce BU1 | `http://bu1.localtest.me:8081` | admin definido no wizard | — |
| nopCommerce BU2 | `http://bu2.localtest.me:8082` | admin definido no wizard | — |
