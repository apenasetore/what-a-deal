import Config

# Desabilita startup da supervision tree nos testes unitarios.
# Cada teste gerencia seus proprios processos via start_supervised!/1.
config :gateway, autostart: false
config :promocao, autostart: false
config :ranking, autostart: false
