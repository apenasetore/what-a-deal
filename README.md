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
                        ┌──────────────────────────────────────┐
                        │                                      │
┌──────────┐            │   Routing Keys:                      │           ┌──────────────┐
│ Gateway  │──publish──▶│   promocao.recebida                  │──consume─▶│ MS Promocao  │
│ (CLI)    │            │   promocao.voto                      │           └──────┬───────┘
│          │◀─consume───│   promocao.publicada                 │                  │
└──────────┘            │   promocao.categoria.destaque        │──publish──────────┘
                        │   promocao.categoria.<categoria>     │
┌──────────┐            │                                      │           ┌──────────────┐
│ Cliente  │◀─consume───│                                      │──consume─▶│ MS Ranking   │
│ Consumer │            │                                      │           └──────┬───────┘
└──────────┘            │                                      │──publish──────────┘
                        │                                      │
                        │                                      │           ┌──────────────┐
                        │                                      │──consume─▶│MS Notificacao│
                        │                                      │           └──────┬───────┘
                        └──────────────────────────────────────┘──publish──────────┘
```

> **Nota:** O sistema utiliza exclusivamente **exchange do tipo topic** com **routing keys hierarquicas**. O roteamento e feito por pattern matching das routing keys nos bindings de cada fila.

### Fluxo de Eventos

1. Loja cadastra promocao via Gateway → `promocao.recebida` → MS Promocao
2. MS Promocao valida assinatura, registra → `promocao.publicada` → Gateway + MS Notificacao
3. MS Notificacao republica por categoria → `promocao.categoria.<categoria>` → Clientes inscritos
4. Usuario vota via Gateway → `promocao.voto` → MS Ranking
5. MS Ranking processa voto, se score >= threshold → `promocao.categoria.destaque` → MS Notificacao
6. MS Notificacao republica hot deal → `promocao.categoria.<categoria>` → Clientes inscritos

### Apps (Umbrella)

| App | Descricao |
|-----|-----------|
| `shared` | Biblioteca compartilhada (crypto, eventos, wrapper RabbitMQ) |
| `gateway` | Interface CLI + publicacao/consumo de eventos |
| `promocao` | Validacao de assinatura e registro de promocoes |
| `ranking` | Processamento de votos e deteccao de hot deals |
| `notificacao` | Distribuicao de notificacoes por categoria via routing keys |
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

# Gerar chaves de assinatura digital (gateway, promocao, ranking)
mix gen_keys

# Rodar testes
mix test

# Verificar formatacao e linter
mix format --check-formatted
mix credo
```

> As chaves geradas por `mix gen_keys` ficam em `apps/shared/priv/keys/` e nao
> sao versionadas. Cada desenvolvedor precisa rodar este comando uma vez apos
> clonar o repositorio. Use `mix gen_keys --force` para regenerar.

RabbitMQ Management UI: http://localhost:15672 (guest/guest)


  # Abrir no navegador
  http://localhost:15672
  # Login: guest / guest

  CLI via Docker

  # Listar exchanges
  docker exec rabbitmq rabbitmqctl list_exchanges

  # Listar filas com mensagens pendentes
  docker exec rabbitmq rabbitmqctl list_queues name
  messages consumers

  # Listar bindings (routing keys ligadas às filas)
  docker exec rabbitmq rabbitmqctl list_bindings

  # Monitorar em tempo real (atualiza a cada 2s)
  watch -n 2 'docker exec rabbitmq rabbitmqctl
  list_queues name messages consumers'

  rabbitmqadmin (mais detalhado)

  # Instalar (dentro do container já vem)
  docker exec rabbitmq rabbitmqadmin list exchanges
  docker exec rabbitmq rabbitmqadmin list queues
  docker exec rabbitmq rabbitmqadmin list bindings

  # Ver mensagens de uma fila sem consumir
  docker exec rabbitmq rabbitmqadmin get
  queue=fila_promocao count=5
  docker exec rabbitmq rabbitmqadmin get
  queue=fila_ranking count=5
  docker exec rabbitmq rabbitmqadmin get
  queue=gateway_promocoes count=5

  Filas do projeto

  As filas que você vai ver são:
  - fila_promocao — consome promocao.recebida
  - fila_ranking — consome promocao.voto
  - gateway_promocoes — consome promocao.publicada

────────────────────────────────────────────────────────
❯  
────────────────────────────────────────────────────────
  ? for shortcuts
