# `max_cases: 1`: o sandbox do Ecto nao e async no SQLite (só um write
# transaction por vez), entao a suíte roda serializada. `capture_log`: cada
# teste captura o Logger e só imprime o que capturou se falhar -- `mix test`
# fica limpo quando tudo passa, e o aviso que explica a falha aparece colado
# no teste que quebrou. Sinais do app (workers, tarefas) continuam capturados
# aqui; o que não é Logger (IO cru) é capturado no teste que o produz, com
# `ExUnit.CaptureIO`.
ExUnit.start(capture_log: true, max_cases: 1)
Ecto.Adapters.SQL.Sandbox.mode(Taina.Repo, :manual)
