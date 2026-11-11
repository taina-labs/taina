defmodule Ypy.PersistenceCase do
  @moduledoc """
  O casco de teste da camada de persistencia: sandbox de conexao e os
  lexicons do kernel carregados, como o produto carrega no boot.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      import Ypy.PersistenceCase

      alias Ypy.TestRepo
    end
  end

  setup do
    :ok = Sandbox.checkout(Ypy.TestRepo)

    {entries, problems} = load_lexicons()

    assert problems == []
    assert map_size(entries) == 2

    :ok
  end

  @doc """
  Recarrega o registro completo (kernel primeiro, produto depois), como o boot.
  O registro mora em `:persistent_term`: um teste do kernel que carregue so o
  diretorio do kernel apagaria os lexicons do produto para os testes seguintes.
  """
  @type params :: map()
  @type path :: Path.t()

  @spec load_lexicons() :: {params(), [{path(), term()}]}
  def load_lexicons do
    Ypy.Lexicon.Registry.load([
      Path.join(File.cwd!(), "priv/ypy/lexicons"),
      Path.join(File.cwd!(), "priv/lexicons")
    ])
  end
end
