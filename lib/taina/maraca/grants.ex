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

  @default_limit 50

  @doc """
  As concessoes que o morador concedeu, da mais recente para a mais antiga,
  revogadas incluidas, paginadas (o `TainaWeb.API.Query` e que le os
  parametros): a pagina de tras um `next_cursor` opaco, e o `:after_cursor`
  devolve o lote seguinte.
  """
  @spec concedidas(Scope.t(), keyword()) ::
          {:ok, %{items: [Concessao.t()], next_cursor: String.t() | nil}}
  def concedidas(%Scope{} = scope, opts \\ []) do
    page(scope, :owner, opts)
  end

  @doc "As concessoes que o morador recebeu, na mesma pagina do `concedidas/2`."
  @spec recebidas(Scope.t(), keyword()) ::
          {:ok, %{items: [Concessao.t()], next_cursor: String.t() | nil}}
  def recebidas(%Scope{} = scope, opts \\ []) do
    page(scope, :reader, opts)
  end

  defp page(%Scope{} = scope, role, opts) do
    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      limit = Keyword.get(opts, :limit, @default_limit)

      rows =
        scope
        |> concessoes_query(role)
        |> apply_cursor(decode_cursor(Keyword.get(opts, :after_cursor)))
        |> limit(^(limit + 1))
        |> Repo.all()
        |> Repo.preload([:leitor, :dono])

      if length(rows) > limit do
        page = Enum.take(rows, limit)
        {:ok, %{items: page, next_cursor: encode_cursor(List.last(page))}}
      else
        {:ok, %{items: rows, next_cursor: nil}}
      end
    end)
  end

  # O cursor e opaco: `concedida_em` em epoch + o id do par. A data nao e
  # unica (duas concessoes no mesmo segundo), entao o id desempata -- o mesmo
  # par (data, id) da linha do tempo do Jaci.
  defp apply_cursor(query, nil), do: query

  defp apply_cursor(query, {%DateTime{} = at, id}) do
    where(query, [c], {c.concedida_em, c.id} < {^at, ^id})
  end

  defp decode_cursor(nil), do: nil

  defp decode_cursor(cursor) when is_binary(cursor) do
    with {:ok, decoded} <- Base.url_decode64(cursor, padding: false),
         [epoch, id] <- String.split(decoded, "|", parts: 2),
         {:ok, at} <- DateTime.from_unix(String.to_integer(epoch)),
         {id, ""} <- Integer.parse(id) do
      {at, id}
    else
      # Cursor ilegivel (ou de outro formato): pagina do comeco em vez de quebrar.
      _ -> nil
    end
  end

  defp encode_cursor(%Concessao{concedida_em: %DateTime{} = at, id: id}) do
    Base.url_encode64("#{DateTime.to_unix(at)}|#{id}", padding: false)
  end

  defp encode_cursor(_sem_data), do: nil

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
  # primeiro), com o id desempatando concessoes do mesmo segundo -- a ordem
  # tem de ser TOTAL para o keyset nao repetir nem pular. O lado do leitor
  # espelha a consulta, com o papel no lugar.
  defp concessoes_query(%Scope{} = scope, :owner) do
    from(c in Concessao,
      where: c.tekoa_id == ^scope.tekoa.id,
      where: c.dono_id == ^scope.ava.id,
      order_by: [desc: c.concedida_em, desc: c.id]
    )
  end

  defp concessoes_query(%Scope{} = scope, :reader) do
    from(c in Concessao,
      where: c.tekoa_id == ^scope.tekoa.id,
      where: c.leitor_id == ^scope.ava.id,
      order_by: [desc: c.concedida_em, desc: c.id]
    )
  end
end
