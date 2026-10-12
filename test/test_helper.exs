# `capture_log`: cada teste captura o Logger e só imprime o que capturou se
# falhar -- `mix test` fica limpo quando tudo passa, e o aviso que explica a
# falha aparece colado no teste que quebrou. Sinais do app (workers, tarefas)
# continuam capturados aqui; o que não é Logger (IO cru) é capturado no teste
# que o produz, com `ExUnit.CaptureIO`.
ExUnit.start(capture_log: true, max_cases: System.schedulers_online() * 2)
Ecto.Adapters.SQL.Sandbox.mode(Taina.Repo, :manual)
