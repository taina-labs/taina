defmodule Taina.Maraca.Grants do
  @moduledoc """
  As duas pontas da concessao para a API (contrato review 0.1.0, C3/C4): as
  que a pessoa concedeu (ela e a dona) e as que recebeu (abriram a casa dela
  para ela ler), revogadas incluidas. Revogar nao apaga o fato social, e o
  fio mostra os dois lados dele.

  A leitura e pela Tekoa do scope, como em todo context; a revogacao em si
  segue no `Taina.Maraca.revogar/2`, que rele o estado e guarda o kernel.
  """

  import Ecto.Query

  alias Taina.Repo
  alias Ypy.Maraca.Concessao
  alias Ypy.PublicId
  alias Ypy.Scope

  @doc "As concessoes que o morador concedeu, da mais recente para a mais antiga, revogadas incluidas."
  @spec concedidas(Scope.t()) :: {:ok, [Concessao.t()]}
  def concedidas(%Scope{} = scope) do
    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      {:ok, scope |> concessoes_query(:owner) |> Repo.all() |> Repo.preload([:leitor, :dono])}
    end)
  end

  @doc "As concessoes que o morador recebeu, da mais recente para a mais antiga, revogadas incluidas."
  @spec recebidas(Scope.t()) :: {:ok, [Concessao.t()]}
  def recebidas(%Scope{} = scope) do
    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      {:ok, scope |> concessoes_query(:reader) |> Repo.all() |> Repo.preload([:leitor, :dono])}
    end)
  end

  @doc "A concessao pelo public_id, dentro da Tekoa."
  @spec get(Scope.t(), String.t()) :: {:ok, Concessao.t()} | {:error, :not_found}
  def get(%Scope{} = scope, public_id) when is_binary(public_id) do
    # O id publico e um tipo proprio no banco: um lixo de cliente nem chega a
    # virar query (o cast do Ecto levantaria).
    if PublicId.valid?(public_id), do: fetch(scope, public_id), else: {:error, :not_found}
  end

  defp fetch(%Scope{} = scope, public_id) do
    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      case Repo.one(from(c in Concessao, where: c.tekoa_id == ^scope.tekoa.id and c.public_id == ^public_id)) do
        nil -> {:error, :not_found}
        %Concessao{} = concessao -> {:ok, concessao}
      end
    end)
  end

  @doc """
  A contagem e o maior `updated_at` do conjunto de um papel, para o ETag da
  colecao (`TainaWeb.API.Etag.token/2`).
  """
  @spec stats(Scope.t(), :owner | :reader) ::
          {:ok, %{count: non_neg_integer(), max_updated_at: DateTime.t() | nil}}
  def stats(%Scope{} = scope, role) do
    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      %{count: count, last: last} =
        Repo.one(
          from(c in concessoes_query(scope, role),
            select: %{count: count(c.id), last: max(c.updated_at)}
          )
        )

      {:ok, %{count: count, max_updated_at: last}}
    end)
  end

  # A mesma ordem do kernel (`Ypy.Maraca.concessoes_concedidas`: mais recente
  # primeiro); o lado do leitor espelha a consulta, com o papel no lugar.
  defp concessoes_query(%Scope{} = scope, :owner) do
    from(c in Concessao,
      where: c.tekoa_id == ^scope.tekoa.id,
      where: c.dono_id == ^scope.ava.id,
      order_by: [desc: c.concedida_em]
    )
  end

  defp concessoes_query(%Scope{} = scope, :reader) do
    from(c in Concessao,
      where: c.tekoa_id == ^scope.tekoa.id,
      where: c.leitor_id == ^scope.ava.id,
      order_by: [desc: c.concedida_em]
    )
  end
end
