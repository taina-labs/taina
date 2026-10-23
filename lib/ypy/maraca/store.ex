defmodule Ypy.Maraca.Store do
  @moduledoc """
  A execucao das queries e changesets do Maraca: `repo` sempre primeiro,
  `tekoa_id` explicito em todo filtro. Nenhuma regra aqui: quem decide e o
  contexto e a politica pura.
  """

  import Ecto.Query, only: [where: 3]

  alias Ypy.Maraca.Concessao
  alias Ypy.Maraca.Pedido
  alias Ypy.Maraca.Queries

  @doc "A Tekoa pelo id."
  def get_tekoa(repo, tekoa_id), do: repo.one(Queries.tekoa(tekoa_id))

  @doc "O ava pelo id, dentro da Tekoa."
  def get_ava(repo, tekoa_id, ava_id) do
    repo.one(where(Queries.avas(tekoa_id), [a], a.id == ^ava_id))
  end

  @doc "O ava pelo public_id, dentro da Tekoa."
  def get_ava_por_public_id(repo, tekoa_id, public_id) do
    repo.one(where(Queries.avas(tekoa_id), [a], a.public_id == ^public_id))
  end

  @doc "O ava pelo username, dentro da Tekoa."
  def get_ava_por_username(repo, tekoa_id, username) do
    repo.one(where(Queries.avas(tekoa_id), [a], a.username == ^username))
  end

  @doc "Quantos zeladores a Tekoa tem."
  def count_zeladores(repo, tekoa_id), do: repo.aggregate(Queries.zeladores(tekoa_id), :count)

  @doc "Quantos moradores ativos a Tekoa tem (o quorum fala deste numero)."
  def count_moradores(repo, tekoa_id), do: repo.aggregate(Queries.moradores(tekoa_id), :count)

  @doc "As concessoes ativas de um leitor, no plano da regra de leitura."
  def concessoes_ativas(repo, tekoa_id, leitor_id), do: repo.all(Queries.concessoes_ativas(tekoa_id, leitor_id))

  @doc "As concessoes que um dono concedeu, mais recentes primeiro."
  def concessoes_concedidas(repo, tekoa_id, dono_id), do: repo.all(Queries.concessoes_concedidas(tekoa_id, dono_id))

  @doc "A concessao pelo id, dentro da Tekoa."
  def get_concessao(repo, tekoa_id, concessao_id) do
    repo.one(where(Concessao, [c], c.tekoa_id == ^tekoa_id and c.id == ^concessao_id))
  end

  @doc "Os pedidos pendentes que o dono recebeu."
  def pedidos_recebidos(repo, tekoa_id, dono_id), do: repo.all(Queries.pedidos_recebidos(tekoa_id, dono_id))

  @doc "Os pedidos que o morador enviou, mais recentes primeiro."
  def pedidos_enviados(repo, tekoa_id, pedinte_id), do: repo.all(Queries.pedidos_enviados(tekoa_id, pedinte_id))

  @doc "O pedido pelo id, dentro da Tekoa."
  def get_pedido(repo, tekoa_id, pedido_id) do
    repo.one(where(Pedido, [p], p.tekoa_id == ^tekoa_id and p.id == ^pedido_id))
  end

  @doc "A chave publica ativa da Tekoa."
  def chave_ativa(repo, tekoa_id), do: repo.one(Queries.chave_ativa(tekoa_id))

  @doc "Aumenta o storage usado da Tekoa (atomico, sem reler)."
  def add_storage(repo, tekoa_id, bytes) do
    {1, _} = repo.update_all(Queries.tekoa(tekoa_id), inc: [storage_used_bytes: bytes])
    :ok
  end

  @doc "Insere pelo changeset dado."
  def insert(repo, changeset), do: repo.insert(changeset)

  @doc "Atualiza pelo changeset dado."
  def update(repo, changeset), do: repo.update(changeset)
end
