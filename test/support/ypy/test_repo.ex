defmodule Ypy.TestRepo do
  @moduledoc """
  O repo dos testes do kernel: SQLite efemero sob o sandbox e, de proposito,
  **sem a guarda de tekoa** do `Taina.Repo`.

  O kernel nao tem `with_tekoa` nem contexto de tekoa implicito (RFC_006 D4):
  ele filtra `tekoa_id` explicitamente em cada query. Rodar as suites do kernel
  contra o repo do produto as faria falhar por um invariante que e do produto,
  nao do kernel. O kernel nao define Repo nenhum; este mora em `test/support`.

  As migracoes do kernel para este repo espelham as de
  `priv/repo/migrations` em `priv/ypy/migrations`, porque o repo do produto
  acrescenta DDL que o kernel nao deve carregar (a trava de uma-Tekoa-por-box
  entre elas). Mudar uma migracao do kernel exige mudar as duas copias.
  """

  use Ecto.Repo, otp_app: :taina, adapter: Ecto.Adapters.SQLite3
end
