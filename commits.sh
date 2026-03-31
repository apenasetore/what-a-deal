#!/bin/bash
# Script de commits da Fase 0 — Setup
# Executar da raiz do repositorio: /mnt/d/UTFPR/2026.1/ICSS30-SD/what-a-deal

set -e

# 1. Roadmap do projeto
git add ROADMAP.md
git commit -m "docs: adicionar roadmap de desenvolvimento do projeto"

# 2. Umbrella project com os 6 apps
git add what_a_deal/mix.exs \
        what_a_deal/config/ \
        what_a_deal/.formatter.exs \
        what_a_deal/apps/shared/ \
        what_a_deal/apps/gateway/ \
        what_a_deal/apps/promocao/ \
        what_a_deal/apps/ranking/ \
        what_a_deal/apps/notificacao/ \
        what_a_deal/apps/cliente/
git commit -m "feat: criar umbrella project com os 6 apps

Apps: shared, gateway, promocao, ranking, notificacao, cliente.
Cada app com supervision tree (--sup)."

# 3. Dependencias
git add what_a_deal/mix.lock
git commit -m "feat: adicionar dependencias base

Root: credo (linter), mox (mocks).
Shared: amqp 4.1 (RabbitMQ), jason (JSON).
Demais apps dependem de shared (in_umbrella)."

# 4. Docker Compose com RabbitMQ
git add what_a_deal/docker-compose.yml
git commit -m "infra: adicionar docker-compose com RabbitMQ

RabbitMQ 4 com management UI (porta 15672) e healthcheck."

# 5. Configuracao do Credo
git add what_a_deal/.credo.exs
git commit -m "config: adicionar configuracao do credo (.credo.exs)"

# 6. GitHub Actions CI
git add what_a_deal/.github/
git commit -m "ci: adicionar workflow GitHub Actions

Roda format --check, credo --strict e mix test.
Inclui servico RabbitMQ e cache de dependencias."

# 7. Gitignore atualizado
git add .gitignore
git commit -m "config: atualizar .gitignore com chaves PEM"

# 8. README
git add what_a_deal/README.md
git commit -m "docs: atualizar README com arquitetura, stack e setup"
