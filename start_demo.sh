#!/usr/bin/env bash
#
# Inicia o sistema what-a-deal em uma sessao tmux com 4 panes:
#
#   +-----------------------------------------------+
#   |                                               |
#   |                BACKEND (~70%)                 |
#   |  gateway+promocao+ranking+notificacao + CLI   |
#   |                                               |
#   +-----------+-------------+---------------------+
#   | Cliente 1 |  Cliente 2  |     Cliente 3       |
#   |  livro    |    jogo     |    eletronico       |
#   | +destaque |             |     +destaque       |
#   +-----------+-------------+---------------------+
#
# Cada cliente roda a partir de apps/cliente, isolado dos outros
# microsservicos, com CLIENTE_CATEGORIAS distintos.
#
# Pre-requisitos:
#   - tmux instalado (brew install tmux)
#   - RabbitMQ rodando (docker compose up -d)
#   - mix gen_keys ja executado
#
# Uso:
#   ./start_demo.sh
#
# Atalhos tmux uteis:
#   Ctrl+B  + setas    -> navegar entre panes
#   Ctrl+B  d          -> detach (sai mas mantem a sessao rodando)
#   Ctrl+B  &          -> mata a janela atual
#   tmux attach -t whatadeal   -> reconectar a sessao depois de detach
#   tmux kill-session -t whatadeal  -> encerrar tudo

set -euo pipefail

SESSION="whatadeal"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
CLIENT_DIR="$PROJECT_ROOT/apps/cliente"

if ! command -v tmux >/dev/null 2>&1; then
  echo "Erro: tmux nao encontrado. Instale com: brew install tmux"
  exit 1
fi

if [ ! -d "$CLIENT_DIR" ]; then
  echo "Erro: nao encontrei $CLIENT_DIR"
  exit 1
fi

# Encerra sessao existente se houver
if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "Sessao tmux '$SESSION' existente. Encerrando..."
  tmux kill-session -t "$SESSION"
fi

# Cria sessao com pane do backend (capturando o pane_id)
tmux new-session -d -s "$SESSION" -n main -c "$PROJECT_ROOT"
backend=$(tmux display-message -p -t "$SESSION:main" '#{pane_id}')

# Pane inferior esquerda (cliente1): split vertical, 30% de altura
cliente1=$(tmux split-window -v -t "$backend" -c "$CLIENT_DIR" -l 30% -P -F '#{pane_id}')

# Pane inferior central (cliente2): split horizontal de cliente1, 67% de largura
cliente2=$(tmux split-window -h -t "$cliente1" -c "$CLIENT_DIR" -l 67% -P -F '#{pane_id}')

# Pane inferior direita (cliente3): split horizontal de cliente2, 50% de largura
cliente3=$(tmux split-window -h -t "$cliente2" -c "$CLIENT_DIR" -l 50% -P -F '#{pane_id}')

# Backend: gateway+promocao+ranking+notificacao com cliente desabilitado
tmux send-keys -t "$backend" \
  "clear && CLIENTE_AUTOSTART=false iex -S mix" Enter

# Cliente 1: livro + destaque
tmux send-keys -t "$cliente1" \
  "clear && CLIENTE_CATEGORIAS=livro CLIENTE_DESTAQUE=true iex -S mix" Enter

# Cliente 2: jogo, sem destaque
tmux send-keys -t "$cliente2" \
  "clear && CLIENTE_CATEGORIAS=jogo CLIENTE_DESTAQUE=false iex -S mix" Enter

# Cliente 3: eletronico + destaque
tmux send-keys -t "$cliente3" \
  "clear && CLIENTE_CATEGORIAS=*  iex -S mix" Enter

# Foco no backend (CLI do gateway) e attach
tmux select-pane -t "$backend"
tmux attach -t "$SESSION"
