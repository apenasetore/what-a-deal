# PromoHub - Roadmap de Desenvolvimento

## Visao Geral do Projeto

Sistema distribuido baseado em microsservicos para gerenciamento e divulgacao de promocoes de produtos. Arquitetura orientada a eventos com RabbitMQ, assinatura digital com criptografia assimetrica, implementado em Elixir.

**Objetivo alem do enunciado:** MVP production-ready, com observabilidade, testes robustos, containerizacao e documentacao de qualidade.

---

## Arquitetura

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

```
1. Loja cadastra promocao via Gateway
   Gateway --[promocao.recebida]--> RabbitMQ --> MS Promocao

2. MS Promocao valida assinatura, registra, publica
   MS Promocao --[promocao.publicada]--> RabbitMQ --> Gateway (atualiza lista local)
                                                  --> MS Notificacao

3. MS Notificacao republica por categoria
   MS Notificacao --[promocao.<categoria>]--> RabbitMQ --> Clientes inscritos

4. Usuario vota em promocao via Gateway
   Gateway --[promocao.voto]--> RabbitMQ --> MS Ranking

5. MS Ranking processa voto, se score >= threshold:
   MS Ranking --[promocao.destaque]--> RabbitMQ --> MS Notificacao

6. MS Notificacao republica hot deal na categoria
   MS Notificacao --[promocao.<categoria>]--> RabbitMQ --> Clientes inscritos
```

---

## Stack Tecnica

| Componente       | Tecnologia                                      |
|------------------|--------------------------------------------------|
| Linguagem        | Elixir                                           |
| Build tool       | Mix                                              |
| Message broker   | RabbitMQ (via `amqp` hex package)                |
| Criptografia     | `:crypto` e `:public_key` (stdlib do Erlang/OTP) |
| Serialização     | Jason (JSON)                                     |
| Testes           | ExUnit + Mox (mocks de conexao RabbitMQ)         |
| Containerizacao  | Docker + Docker Compose                          |
| CI               | GitHub Actions                                   |
| Observabilidade  | Logger estruturado + Telemetry                   |
| Linter/Formatter | `mix format` + Credo                             |

---

## Estrutura do Repositorio (Umbrella Project)

```
promo_hub/
├── docker-compose.yml          # RabbitMQ + todos os servicos
├── Dockerfile                  # Multi-stage build para todos os apps
├── ROADMAP.md
├── README.md
├── .github/
│   └── workflows/
│       └── ci.yml              # format --check, credo, test
├── config/
│   ├── config.exs              # config compartilhada
│   ├── dev.exs
│   ├── test.exs
│   └── prod.exs
├── apps/
│   ├── shared/                 # Biblioteca compartilhada (crypto, eventos, serialização)
│   │   ├── lib/
│   │   │   ├── shared/
│   │   │   │   ├── crypto.ex           # Assinatura digital e verificação
│   │   │   │   ├── event.ex            # Struct de evento + envelope
│   │   │   │   ├── event_publisher.ex  # Behaviour para publicar eventos
│   │   │   │   ├── event_consumer.ex   # Behaviour para consumir eventos
│   │   │   │   └── rabbitmq.ex         # Wrapper de conexão AMQP
│   │   │   └── shared.ex
│   │   ├── test/
│   │   └── mix.exs
│   ├── gateway/                # MS Gateway (CLI + pub/sub)
│   │   ├── lib/
│   │   │   ├── gateway/
│   │   │   │   ├── application.ex
│   │   │   │   ├── cli.ex              # Interface terminal interativa
│   │   │   │   ├── publisher.ex        # Publica promocao.recebida, promocao.voto
│   │   │   │   ├── consumer.ex         # Consome promocao.publicada
│   │   │   │   └── promo_store.ex      # Agent/GenServer - lista local de promoções validadas
│   │   │   └── gateway.ex
│   │   ├── test/
│   │   └── mix.exs
│   ├── promocao/               # MS Promocao (validação + registro)
│   │   ├── lib/
│   │   │   ├── promocao/
│   │   │   │   ├── application.ex
│   │   │   │   ├── consumer.ex         # Consome promocao.recebida
│   │   │   │   ├── publisher.ex        # Publica promocao.publicada
│   │   │   │   ├── validator.ex        # Valida assinatura digital
│   │   │   │   └── store.ex            # Armazena promoções registradas
│   │   │   └── promocao.ex
│   │   ├── test/
│   │   └── mix.exs
│   ├── ranking/                # MS Ranking (votos + hot deals)
│   │   ├── lib/
│   │   │   ├── ranking/
│   │   │   │   ├── application.ex
│   │   │   │   ├── consumer.ex         # Consome promocao.voto
│   │   │   │   ├── publisher.ex        # Publica promocao.destaque
│   │   │   │   ├── vote_processor.ex   # Lógica de processamento de votos
│   │   │   │   └── score_calculator.ex # Calcula score e threshold de hot deal
│   │   │   └── ranking.ex
│   │   ├── test/
│   │   └── mix.exs
│   ├── notificacao/            # MS Notificação (fan-out por categoria)
│   │   ├── lib/
│   │   │   ├── notificacao/
│   │   │   │   ├── application.ex
│   │   │   │   ├── consumer.ex         # Consome promocao.publicada + promocao.destaque
│   │   │   │   └── publisher.ex        # Publica promocao.<categoria>
│   │   │   └── notificacao.ex
│   │   ├── test/
│   │   └── mix.exs
│   └── cliente/                # Processo cliente consumidor
│       ├── lib/
│       │   ├── cliente/
│       │   │   ├── application.ex
│       │   │   ├── subscriber.ex       # Se inscreve em categorias de interesse
│       │   │   └── display.ex          # Exibe notificações no terminal
│       │   └── cliente.ex
│       ├── test/
│       └── mix.exs
└── promo_hub_umbrella/
    └── mix.exs                 # Umbrella root
```

---

## Fases de Desenvolvimento

### Fase 0 — Setup (31/03)
**Quem:** Juntos (pair programming)
**Objetivo:** Infraestrutura base pronta, ambos com ambiente funcional.

- [x] Criar repositorio GitHub (privado), configurar branch protection em `main`
- [x] Criar umbrella project: `mix new promo_hub --umbrella`
- [x] Adicionar os 6 apps ao umbrella (`shared`, `gateway`, `promocao`, `ranking`, `notificacao`, `cliente`)
- [x] Criar `docker-compose.yml` com RabbitMQ (management UI na porta 15672)
- [x] Adicionar dependencias base: `amqp`, `jason`, `credo`, `mox`
- [x] Configurar `mix format` e `.credo.exs`
- [x] Criar GitHub Actions CI basico (format --check, credo, test)
- [x] Verificar que `docker compose up` + `mix test` funciona nos dois ambientes
- [x] Criar `.gitignore` adequado

**Entregavel:** `mix test` passa, CI verde, RabbitMQ rodando em Docker.

---

### Fase 1 — Shared Library: Crypto + Eventos (01/04)
**Quem:** Ambos, alternando driver/navigator
**Objetivo:** Fundacao compartilhada que todos os microsservicos usam.

- [x] **Shared.Crypto** — Gerar par de chaves RSA (por microsservico), assinar payload (SHA256withRSA), verificar assinatura
  - Gerar chaves: `:public_key.generate_key({:rsa, 2048, 65537})`
  - Assinar: `:public_key.sign(payload, :sha256, private_key)`
  - Verificar: `:public_key.verify(payload, :sha256, signature, public_key)`
  - Armazenar chaves em arquivos PEM por servico (em `priv/keys/`)
- [x] **Shared.Event** — Struct padrao para todos os eventos:
  ```elixir
  %Event{
    id: UUID,
    type: "promocao.recebida",  # routing key
    payload: %{},               # dados do evento
    source: "gateway",          # microsservico de origem
    signature: <<binary>>,      # assinatura digital
    timestamp: DateTime
  }
  ```
- [x] **Shared.Event.Envelope** — Serializar/deserializar evento para JSON (com signature em Base64)
- [x] **Shared.RabbitMQ** — Wrapper de conexao:
  - Conectar, declarar exchange (topic, "promocoes"), declarar fila, bind, publish, consume
  - Reconnect automatico com backoff exponencial
  - Usar `GenServer` para gerenciar conexao
- [x] **Testes unitarios** para crypto (assinar, verificar, rejeitar assinatura invalida)
- [x] **Testes unitarios** para serialização de eventos

**Entregavel:** `mix test apps/shared` verde, crypto e eventos funcionando isoladamente.

---

### Fase 2 — MS Promocao + Gateway (02-03/04)
**Quem:** Um desenvolve Gateway, outro MS Promocao. Depois trocam para review e aprender a outra parte.
**Objetivo:** Fluxo basico de cadastro de promocao funcionando end-to-end.

#### Gateway
- [ ] CLI interativa com menu:
  ```
  === PromoHub ===
  1. Cadastrar promoção
  2. Listar promoções
  3. Votar em promoção
  4. Sair
  ```
- [ ] Cadastro de promocao: nome, descricao, preco_original, preco_promocional, categoria, loja
- [ ] Publisher: publica `promocao.recebida` com assinatura digital
- [ ] Consumer: consome `promocao.publicada`, armazena em PromoStore (GenServer/Agent)
- [ ] Listar promocoes: exibe do PromoStore local (apenas as validadas)

#### MS Promocao
- [ ] Consumer: consome `promocao.recebida`
- [ ] Valida assinatura digital (chave publica do Gateway)
- [ ] Registra promocao (Store com ETS ou Agent)
- [ ] Publica `promocao.publicada` com assinatura digital

#### Integracao
- [ ] Teste end-to-end: Gateway cadastra -> Promocao valida e publica -> Gateway recebe e lista
- [ ] Teste de rejeicao: evento com assinatura invalida e descartado

**Entregavel:** Cadastrar uma promocao via terminal e ver ela aparecer na listagem.

---

### Fase 3 — MS Ranking + Votacao (04/04)
**Quem:** Trocar papeis — quem fez Gateway agora faz Ranking, quem fez Promocao agora faz a parte de votacao do Gateway.
**Objetivo:** Votacao funcionando, hot deals sendo detectados.

#### Gateway (extensao)
- [ ] Opcao de votar: usuario escolhe promocao e voto (+1 ou -1)
- [ ] Publica `promocao.voto` com assinatura

#### MS Ranking
- [ ] Consumer: consome `promocao.voto`, valida assinatura
- [ ] VoteProcessor: mantém contagem de votos por promocao (GenServer com ETS)
- [ ] ScoreCalculator: calcula score (ex: `votos_positivos - votos_negativos`)
- [ ] Se score >= threshold (ex: 10), publica `promocao.destaque` com assinatura
- [ ] Idempotencia: nao publicar destaque multiplas vezes para a mesma promocao

**Entregavel:** Votar em promocoes, ver hot deal sendo gerado quando threshold e atingido.

---

### Fase 4 — MS Notificacao + Cliente Consumer (05/04)
**Quem:** Novamente trocar — cada um pega o componente que ainda nao desenvolveu.
**Objetivo:** Notificacoes chegando nos clientes por categoria.

#### MS Notificacao
- [ ] Consumer: consome `promocao.publicada` e `promocao.destaque`, valida assinatura
- [ ] Extrai categoria da promocao
- [ ] Para `promocao.publicada`: publica em `promocao.<categoria>` (ex: `promocao.livro`)
- [ ] Para `promocao.destaque`: publica em `promocao.<categoria>` com marcacao "HOT DEAL"

#### Cliente Consumer
- [ ] Configuracao de categorias de interesse (hardcoded, mas parametrizavel por instancia)
- [ ] Cria fila exclusiva e faz bind nas routing keys de interesse
- [ ] Exibe notificacoes formatadas no terminal:
  ```
  [2026-04-15 14:30:22] [livro] Nova promoção: "Clean Code" R$89.90 -> R$45.00
  [2026-04-15 14:31:05] [livro] 🔥 HOT DEAL: "Clean Code" R$89.90 -> R$45.00
  ```
- [ ] Permitir rodar multiplas instancias com categorias diferentes

**Entregavel:** Sistema completo funcionando — cadastro, votacao, hot deal, notificacao.

---

### Fase 5 — Hardening & Production Readiness (06-07/04)
**Quem:** Juntos (pair programming)
**Objetivo:** Deixar o sistema robusto e apresentavel.

- [ ] **Observabilidade**
  - Logger estruturado com metadata (service, event_id, routing_key)
  - Telemetry events para metricas: eventos publicados, consumidos, rejeitados
  - Health check endpoint (opcional: Plug/Bandit simples)
- [ ] **Resiliencia**
  - Reconnect automatico ao RabbitMQ com backoff exponencial
  - Graceful shutdown (fechar conexoes AMQP no terminate/1)
  - Dead letter queue para eventos que falharam
- [ ] **Testes**
  - Testes unitarios com boa cobertura (crypto, vote processing, score calculation)
  - Testes de integracao com RabbitMQ real (tagged, rodam so no CI ou com `--include integration`)
  - Testes de rejeicao de assinatura invalida em cada microsservico
- [ ] **Docker**
  - Dockerfile multi-stage (build + runtime)
  - `docker-compose.yml` com todos os servicos + RabbitMQ
  - `docker compose up` sobe o sistema inteiro
- [ ] **Documentacao**
  - README com instrucoes de setup, arquitetura, como rodar
  - Decisoes de design documentadas (ADRs simples no README)

**Entregavel:** `docker compose up` e o sistema inteiro funciona. Testes passam no CI.

---

### Fase 6 — Extras / "Alem do Enunciado" (somente se sobrar tempo)
**Quem:** Escolher por interesse, mas ambos revisam.

Ideias priorizadas por impacto no aprendizado:

- [ ] **Supervision trees bem desenhadas** — cada app com supervisor, restart strategies adequadas (one_for_one vs rest_for_one)
- [ ] **Web UI com Phoenix LiveView** — substituir CLI por interface web (grande aprendizado, mas demanda tempo)
- [ ] **Persistencia com SQLite/Ecto** — substituir Agent/ETS por banco real
- [ ] **Rate limiting** — limitar votos por usuario/tempo
- [ ] **Message TTL e expiracao** — promocoes expiram apos X tempo
- [ ] **Distributed tracing** — correlation ID propagado entre servicos
- [ ] **Prometheus + Grafana** — dashboards de metricas
- [ ] **Property-based testing** — StreamData para testar crypto e serialização

---

## Cronograma (Entrega: 09/04/2026)

**9 dias uteis (31/03 a 08/04). Dia 09/04 e defesa.**

```
31/03 (ter):  Fase 0 — Setup completo (umbrella, Docker, CI)
01/04 (qua):  Fase 1 — Shared library (crypto + eventos + wrapper RabbitMQ)
02/04 (qui):  Fase 2 — Gateway CLI + MS Promocao (dividir)
03/04 (sex):  Fase 2 — Integracao Gateway <-> Promocao, testes
04/04 (sab):  Fase 3 — Ranking + votacao no Gateway (trocar papeis)
05/04 (dom):  Fase 4 — MS Notificacao + Cliente Consumer (trocar papeis)
06/04 (seg):  Fase 5 — Hardening: testes, resiliencia, Docker compose completo
07/04 (ter):  Fase 5 — Polimento, documentacao, testes de integracao
08/04 (qua):  Buffer + ensaio de defesa (rodar demo completa, preparar explicacao)
09/04 (qui):  DEFESA
```

> **Ritmo:** Fases 0 e 1 juntos (pair). Fases 2-4 dividir e trocar papeis. Fases 5+ juntos.
> **Prioridade:** Se o tempo apertar, cortar Fase 6 (extras) e focar em ter o fluxo completo funcionando com Docker.

---

## Protocolo de Trabalho em Dupla

### Principios

1. **Ambos aprendem tudo.** Nenhuma parte do sistema e "territorio" de um so.
2. **Atrito minimo.** O protocolo existe para ajudar, nao para burocratizar.
3. **Comunicacao assincrona por padrao.** Sincronizar so quando agrega valor.

### Fluxo Diario

```
1. Olhar o board (issues do GitHub) — ver o que esta em andamento e o que vem a seguir.
2. Pegar uma tarefa, mover para "In Progress", criar branch.
3. Desenvolver. Commitar com mensagens claras.
4. Abrir PR quando terminar. Descrever O QUE e POR QUE.
5. Parceiro faz review — ler o codigo, rodar, comentar. Aprovar ou pedir mudancas.
6. Merge na main.
```

### Regras Simples

| Regra | Detalhe |
|-------|---------|
| **Branch por tarefa** | `feat/gateway-cli`, `feat/ranking-votes`, etc. Nunca commitar direto na `main`. |
| **PR obrigatorio** | Todo codigo entra via Pull Request. Nao precisa ser gigante — PRs pequenos sao melhores. |
| **Review obrigatorio** | O parceiro precisa aprovar. Isso garante que ambos leiam todo o codigo. |
| **CI deve passar** | Nao fazer merge com CI vermelho. |
| **Rotacao de papeis** | A cada fase, trocar quem faz o que. Quem fez Gateway na Fase 2 faz Ranking na Fase 3. |

### Comunicacao

| Tipo | Canal | Quando |
|------|-------|--------|
| **Decisao de design** | Comentario na Issue/PR do GitHub | Antes de implementar algo nao trivial |
| **Review** | GitHub PR | Quando o PR esta pronto |
| **Duvida rapida** | WhatsApp/Telegram | Quando esta travado e precisa de input |
| **Pair programming** | Discord (tela compartilhada) | Fase 0, problemas complexos, ou quando quiserem |
| **Status diario** | Nao precisa | O board do GitHub ja mostra o status |

### Quando Fazer Pair Programming (Sincrono)

- Setup inicial (Fase 0) — alinhar ambiente e convencoes
- Quando alguem esta travado ha mais de 30 min
- Decisoes de design que afetam multiplos servicos
- Debugar problemas de integracao entre servicos
- Preparar a defesa do trabalho

### Quando Trabalhar Assincrono

- Tudo que nao esta na lista acima
- Implementacao de features bem definidas
- Escrever testes
- Code review

### Gestao de Tarefas (GitHub Issues + Projects)

Usar **GitHub Issues** como tarefas e **GitHub Projects** (board Kanban) com colunas:

```
Backlog → In Progress → In Review → Done
```

Cada Issue deve ter:
- Titulo claro (ex: "Implementar Shared.Crypto — assinatura RSA")
- Descricao com criterios de aceite
- Label de fase (`fase-1`, `fase-2`, etc.)
- Assignee (quem vai fazer)

### Convencoes de Codigo

- `mix format` antes de commitar (CI valida)
- `mix credo` sem warnings
- Nomes de modulos, funcoes e variaveis em ingles (padrao Elixir)
- Comentarios e documentacao podem ser em portugues
- Mensagens de commit em portugues ou ingles (decidir juntos na Fase 0 e manter consistente)

### Resolucao de Conflitos Tecnicos

1. Quem tem a opiniao mais forte explica o racional em 2 minutos
2. Se nao resolver, prototipar as duas abordagens (5 min cada)
3. Se ainda nao resolver, ir com a opcao mais simples — sempre da pra mudar depois

---

## Checklist de Entrega (Requisitos do Enunciado)

### Clientes Consumidores (0,2)
- [ ] Cliente consome notificacoes de categorias de interesse
- [ ] Interesse em multiplas categorias + destaque
- [ ] Routing keys hierarquicas com exchange topic
- [ ] Cada cliente cria propria fila com bindings

### MS Gateway (0,5)
- [ ] Interface terminal interativa (cadastrar, listar, votar)
- [ ] Assinatura digital em todos os eventos publicados
- [ ] Publica `promocao.recebida` e `promocao.voto`
- [ ] Consome `promocao.publicada`, mantem lista local

### MS Promocao (0,3)
- [ ] Consome `promocao.recebida`, valida assinatura
- [ ] Registra promocao, assina e publica `promocao.publicada`

### MS Ranking (0,5)
- [ ] Consome `promocao.voto`, valida assinatura
- [ ] Processa voto, atualiza contador, calcula score
- [ ] Se score >= threshold, assina e publica `promocao.destaque`

### MS Notificacao (0,5)
- [ ] Consome `promocao.publicada` e `promocao.destaque`, valida assinatura
- [ ] Publica `promocao.<categoria>` para cada promocao
- [ ] Hot deal inclui marcacao na notificacao

### Criptografia
- [ ] Cada servico (exceto Notificacao) assina eventos com chave privada
- [ ] Todos os consumidores validam assinatura com chave publica
- [ ] Evento com assinatura invalida e descartado
