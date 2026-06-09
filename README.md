# What A Deal

### Distributed System -- Product Promotion Management

Sistema distribuido baseado em microsservicos para gerenciamento e divulgacao de promocoes de produtos. Arquitetura orientada a eventos com RabbitMQ, assinatura digital com criptografia assimetrica (RSA), API REST com notificacoes em tempo real via SSE e envio de emails, implementado em Elixir.

**Curso:** Sistemas Distribuidos
**Alunos:** Etore Maloso Tronconi e Henrique Gomes Pinto Bubniak
**Professor:** Ana Cristina Barreiras Kochem Vendramin
**Instituicao:** UTFPR

---

## Arquitetura

O sistema e composto por **4 microsservicos** + **1 biblioteca compartilhada** + **1 cliente consumidor**, comunicando-se via **RabbitMQ** com um **topic exchange** (`promocoes`).

```
                        RabbitMQ (Exchange: topic "promocoes")
                        ┌──────────────────────────────────────┐
                        │                                      │
┌──────────┐            │   Routing Keys:                      │           ┌──────────────┐
│ Gateway  │──publish──▶│   promocao.recebida                  │──consume─▶│ MS Promocao  │
│ (REST +  │            │   promocao.voto                      │           └──────┬───────┘
│  SSE)    │◀─consume───│   promocao.publicada                 │                  │
└────┬─────┘            │   promocao.categoria.destaque        │──publish──────────┘
     │ SSE              │   promocao.categoria.<categoria>     │
     ▼                  │                                      │           ┌──────────────┐
┌──────────┐            │                                      │──consume─▶│ MS Ranking   │
│ Frontend/│            │                                      │           └──────┬───────┘
│ Browser  │            │                                      │──publish──────────┘
└──────────┘            │                                      │
                        │                                      │           ┌──────────────┐
┌──────────┐            │                                      │──consume─▶│MS Notificacao│
│ Cliente  │◀─consume───│                                      │           └──────┬───────┘
│ Consumer │            │                                      │──publish──────────┘
└──────────┘            └──────────────────────────────────────┘    (tambem envia email
                                                                      via SMTP/Gmail)
```

> **Nota:** O sistema utiliza exclusivamente **exchange do tipo topic** com **routing keys hierarquicas**. O roteamento e feito por pattern matching das routing keys nos bindings de cada fila.

### Fluxo de Eventos

1. Loja se cadastra via `POST /store` enviando sua **chave publica RSA** (PEM); o Gateway guarda no `StoreStore`
2. Loja cadastra promocao via `POST /deals` com **assinatura digital** do payload; o Gateway verifica a assinatura com a chave publica da loja, assina o evento com sua propria chave privada e publica → `promocao.recebida` → MS Promocao
3. MS Promocao valida a assinatura do Gateway e republica assinado → `promocao.publicada` → Gateway + MS Notificacao
4. MS Notificacao valida a assinatura, republica por categoria (`promocao.categoria.<categoria>`) e **envia email** para a loja avisando que a promocao foi publicada
5. Gateway consome `promocao.publicada` (guarda no `DealStore`) e `promocao.categoria.*`, repassando as notificacoes via **SSE** apenas para os clientes inscritos naquela categoria
6. Usuario vota via `POST /vote` → Gateway assina e publica `promocao.voto` → MS Ranking
7. MS Ranking valida a assinatura e contabiliza o voto; se score >= 3 → `promocao.categoria.destaque` → MS Notificacao + Gateway
8. MS Notificacao republica o **hot deal** por categoria e envia email para a loja; o Gateway repassa o destaque via SSE aos inscritos em `destaque`

Eventos com assinatura invalida sao **descartados** em todos os consumidores (com log de warning).

### Apps (Umbrella)

| App | Descricao |
|-----|-----------|
| `shared` | Biblioteca compartilhada: crypto RSA (`Shared.Crypto`), eventos assinados (`Shared.Event` + `Envelope`), wrapper RabbitMQ com reconexao automatica (`Shared.RabbitMQ`), task `mix gen_keys` |
| `gateway` | API REST (porta 4000) + SSE para o frontend; publica `promocao.recebida` e `promocao.voto`; consome `promocao.publicada` e `promocao.categoria.#`; mantem caches em memoria (deals, lojas, inscricoes) |
| `promocao` | Valida assinatura de `promocao.recebida` e republica como `promocao.publicada` |
| `ranking` | Contabiliza votos (`VoteStore`); ao atingir threshold (score >= 3) publica `promocao.categoria.destaque` |
| `notificacao` | Valida eventos, republica notificacoes JSON por categoria e envia emails (Swoosh + SMTP Gmail) para a loja |
| `cliente` | Consumidor terminal de notificacoes por categoria (fila exclusiva `cliente_<hex>`, configuravel por env vars) |

## Stack

| Componente | Tecnologia |
|------------|------------|
| Linguagem | Elixir 1.17+ |
| Build tool | Mix (umbrella) |
| Message broker | RabbitMQ (`amqp ~> 4.1`) |
| HTTP server | Plug + Cowboy (porta 4000) |
| Tempo real | SSE (`sse` + `event_bus`) |
| Email | Swoosh + SMTP (Gmail App Password) |
| Criptografia | RSA 2048 / SHA-256 via `:crypto` e `:public_key` (stdlib Erlang/OTP) |
| Serializacao | Jason |
| Testes | ExUnit + Mox |
| Linter | Credo |
| Containerizacao | Docker + Docker Compose |
| CI | GitHub Actions |

## Setup

### Pre-requisitos

- Elixir 1.17+
- Docker + Docker Compose
- RabbitMQ (via Docker ou local na porta 5672)

### Instalacao

```bash
# Subir RabbitMQ
docker compose up -d

# Instalar dependencias
mix deps.get

# Gerar chaves de assinatura digital (gateway, promocao, ranking)
mix gen_keys

# Configurar credenciais de email (MS Notificacao)
cp .env.example .env   # editar com GMAIL_USER e GMAIL_APP_PASSWORD

# Rodar testes
mix test

# Verificar formatacao e linter
mix format --check-formatted
mix credo
```

> As chaves geradas por `mix gen_keys` ficam em `apps/shared/priv/keys/` e nao
> sao versionadas. Cada desenvolvedor precisa rodar este comando uma vez apos
> clonar o repositorio. Use `mix gen_keys --force` para regenerar.

### Rodando

```bash
# Carregar o .env no shell (necessario para o envio de email)
set -a; source .env; set +a

# Subir todos os microsservicos (umbrella) + API na porta 4000
iex -S mix
```

O `.env` contem as credenciais do Gmail usadas pelo MS Notificacao
(`GMAIL_USER` e `GMAIL_APP_PASSWORD` — App Password de 16 caracteres gerado em
https://myaccount.google.com/apppasswords, nao a senha de login). Sem essas
variaveis o sistema funciona normalmente, apenas o envio de email falha com log de erro.

### Rodando clientes extras (terminais separados)

Cada cliente consumidor cria uma fila exclusiva (`cliente_<8 hex>`, `auto_delete`), entao varias instancias podem rodar em paralelo. Para nao subir o backend duplicado, inicie a partir de `apps/cliente`:

```bash
# Terminal 2 (cliente apenas em "jogo", sem destaque):
cd apps/cliente
CLIENTE_CATEGORIAS=jogo CLIENTE_DESTAQUE=false iex -S mix

# Terminal 3 (cliente em "eletronico" + hot deals):
cd apps/cliente
CLIENTE_CATEGORIAS=eletronico CLIENTE_DESTAQUE=true iex -S mix
```

Defaults (em `config/dev.exs`): `categorias: ["livro", "jogo"]`, `destaque: true`.

## API REST (Gateway — `http://localhost:4000`)

| Metodo | Rota | Descricao |
|--------|------|-----------|
| `GET` | `/health` | Health check |
| `POST` | `/store` | Cadastra loja: `{"nome", "pub_key"}` (chave publica PEM) |
| `GET` | `/deals` | Lista promocoes validadas pelo MS Promocao |
| `POST` | `/deals` | Cadastra promocao (exige campo `signature` assinado pela loja) |
| `POST` | `/vote` | Vota: `{"promo": {...}, "vote": "up" \| "down"}` |
| `POST` | `/subscription` | Inscreve cliente em categoria: `{"client_name", "category"}` |
| `GET` | `/subscription/:client_name` | Lista categorias do cliente |
| `DELETE` | `/subscription` | Remove inscricao: `{"client_name", "category"}` |
| `GET` | `/stream/:client_name` | **SSE**: stream de notificacoes das categorias inscritas |

Todos os endpoints com body exigem `Content-Type: application/json`.

### Assinatura da loja (`POST /deals`)

O campo `signature` e a assinatura RSA/SHA-256 (Base64) da **mensagem canonica**
construida pela concatenacao com `|`, na ordem:

```
loja|nome|descricao|categoria|email|preco_original|preco_promocional
```

com os precos formatados com 2 casas decimais (equivalente ao `Number.toFixed(2)` do JS).
O Gateway verifica contra a chave publica cadastrada no `POST /store`; assinatura
ausente ou invalida retorna `401`.

### SSE (`GET /stream/:client_name`)

Ao conectar, o cliente recebe um evento `ready`. Depois, cada notificacao das
categorias em que esta inscrito (incluindo `destaque`, se inscrito) chega como
evento SSE com o JSON da notificacao:

```bash
curl -N http://localhost:4000/stream/alice
```

## Demonstracao de assinatura invalida

Para demonstrar que os consumidores descartam eventos forjados, no `iex`:

```elixir
# MS Promocao descarta (assinado com chave RSA falsa):
Gateway.Publisher.publish_fake_promocao()

# MS Ranking descarta:
Gateway.Publisher.publish_fake_voto()
```

## RabbitMQ — Inspecao e Debug

Management UI: http://localhost:15672 (guest/guest)

```bash
# Listar exchanges
docker exec what_a_deal_rabbitmq rabbitmqctl list_exchanges

# Listar filas com mensagens pendentes e consumidores
docker exec what_a_deal_rabbitmq rabbitmqctl list_queues name messages consumers

# Listar bindings (routing keys ligadas as filas)
docker exec what_a_deal_rabbitmq rabbitmqctl list_bindings

# Monitorar em tempo real (atualiza a cada 2s)
watch -n 2 'docker exec what_a_deal_rabbitmq rabbitmqctl list_queues name messages consumers'

# Ver mensagens de uma fila sem consumir
docker exec what_a_deal_rabbitmq rabbitmqadmin get queue=fila_promocao count=5
```

### Filas do projeto

| Fila | Routing keys (bindings) | Consumidor |
|------|--------------------------|------------|
| `fila_promocao` | `promocao.recebida` | MS Promocao |
| `fila_ranking` | `promocao.voto` | MS Ranking |
| `fila_notificacao` | `promocao.publicada`, `promocao.categoria.destaque` | MS Notificacao |
| `gateway_promocoes` | `promocao.publicada`, `promocao.categoria.#` | Gateway (DealStore + SSE) |
| `cliente_<hex>` | `promocao.categoria.<categoria>` [+ `promocao.categoria.destaque`] | Cliente Consumer (uma por instancia, `auto_delete`) |
