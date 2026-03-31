# What A Deal

### Distributed System -- Product Promotion Management

Sistema distribuido baseado em microsservicos para gerenciamento e divulgacao de promocoes de produtos. Arquitetura orientada a eventos com RabbitMQ, assinatura digital com criptografia assimetrica, implementado em Elixir.

**Curso:** Sistemas Distribuidos
**Alunos:** Etore Maloso Tronconi e Henrique Gomes Pinto Bubniak
**Professor:** Ana Cristina Barreiras Kochem Vendramin
**Instituicao:** UTFPR

---

## Arquitetura

O sistema e composto por **4 microsservicos** + **1 biblioteca compartilhada** + **1 cliente consumidor**, comunicando-se via **RabbitMQ** com um **topic exchange**.

```
                        RabbitMQ (Exchange: topic "promocoes")
                        ┌─────────────────────────────────┐
                        │                                 │
┌──────────┐            │   Routing Keys:                 │           ┌──────────────┐
│ Gateway  │──publish──▶│   promocao.recebida             │──consume─▶│ MS Promocao  │
│ (CLI)    │            │   promocao.voto                 │           └──────┬───────┘
│          │◀─consume───│   promocao.publicada            │                  │
└──────────┘            │   promocao.destaque             │──publish──────────┘
                        │   promocao.<categoria>          │
┌──────────┐            │                                 │           ┌──────────────┐
│ Cliente  │◀─consume───│                                 │──consume─▶│ MS Ranking   │
│ Consumer │            │                                 │           └──────┬───────┘
└──────────┘            │                                 │──publish──────────┘
                        │                                 │
                        │                                 │           ┌──────────────┐
                        │                                 │──consume─▶│MS Notificacao│
                        │                                 │           └──────┬───────┘
                        └─────────────────────────────────┘──publish──────────┘
```

### Fluxo de Eventos

1. Loja cadastra promocao via Gateway → `promocao.recebida` → MS Promocao
2. MS Promocao valida assinatura, registra → `promocao.publicada` → Gateway + MS Notificacao
3. MS Notificacao republica por categoria → `promocao.<categoria>` → Clientes inscritos
4. Usuario vota via Gateway → `promocao.voto` → MS Ranking
5. MS Ranking processa voto, se score >= threshold → `promocao.destaque` → MS Notificacao
6. MS Notificacao republica hot deal → `promocao.<categoria>` → Clientes inscritos

### Apps (Umbrella)

| App | Descricao |
|-----|-----------|
| `shared` | Biblioteca compartilhada (crypto, eventos, wrapper RabbitMQ) |
| `gateway` | Interface CLI + publicacao/consumo de eventos |
| `promocao` | Validacao de assinatura e registro de promocoes |
| `ranking` | Processamento de votos e deteccao de hot deals |
| `notificacao` | Fan-out de notificacoes por categoria |
| `cliente` | Consumidor de notificacoes por categoria |

## Stack

| Componente | Tecnologia |
|------------|------------|
| Linguagem | Elixir 1.17+ |
| Build tool | Mix (umbrella) |
| Message broker | RabbitMQ (`amqp ~> 4.1`) |
| Criptografia | `:crypto` e `:public_key` (stdlib Erlang/OTP) |
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

# Rodar testes
mix test

# Verificar formatacao e linter
mix format --check-formatted
mix credo
```

RabbitMQ Management UI: http://localhost:15672 (guest/guest)


## Test ruleset no pushs to main  Test ruleset no pushs to main 