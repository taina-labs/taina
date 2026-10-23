defmodule Ypy.Maraca.Queries do
  @moduledoc """
  Construtores de query do Maraca, com `tekoa_id` explicito em todo `WHERE`
  (RFC_006 D4). Nenhum deles toca repo: os stores executam.
  """

  import Ecto.Query

  alias Ypy.Maraca.Ava
  alias Ypy.Maraca.Concessao
  alias Ypy.Maraca.Pedido
  alias Ypy.Maraca.Tekoa
  alias Ypy.Maraca.TekoaKey

  @doc "A Tekoa pelo id do banco."
  def tekoa(tekoa_id), do: from(t in Tekoa, where: t.id == ^tekoa_id)

  @doc "Os avas de uma Tekoa."
  def avas(tekoa_id), do: from(a in Ava, where: a.tekoa_id == ^tekoa_id)

  @doc "Os moradores ativos: aceitaram convite e nao foram desativados."
  def moradores(tekoa_id) do
    from(a in avas(tekoa_id),
      where: not is_nil(a.activated_at),
      where: is_nil(a.deactivated_at)
    )
  end

  @doc "Os zeladores de uma Tekoa."
  def zeladores(tekoa_id), do: from(a in avas(tekoa_id), where: a.papel == :zelador)

  @doc "As concessoes ativas de um leitor, no plano que a regra de leitura fala."
  def concessoes_ativas(tekoa_id, leitor_id) do
    from(c in Concessao,
      where: c.tekoa_id == ^tekoa_id,
      where: c.leitor_id == ^leitor_id,
      where: is_nil(c.revogada_em),
      select: %{leitor_id: c.leitor_id, recurso: c.recurso}
    )
  end

  @doc "As concessoes que um dono concedeu, mais recentes primeiro."
  def concessoes_concedidas(tekoa_id, dono_id) do
    from(c in Concessao,
      where: c.tekoa_id == ^tekoa_id,
      where: c.dono_id == ^dono_id,
      order_by: [desc: c.concedida_em]
    )
  end

  @doc "Os pedidos pendentes de um dono."
  def pedidos_recebidos(tekoa_id, dono_id) do
    from(p in Pedido,
      where: p.tekoa_id == ^tekoa_id,
      where: p.dono_id == ^dono_id,
      where: p.status == :pendente,
      order_by: [desc: p.inserted_at]
    )
  end

  @doc "Os pedidos que um morador fez, mais recentes primeiro."
  def pedidos_enviados(tekoa_id, pedinte_id) do
    from(p in Pedido,
      where: p.tekoa_id == ^tekoa_id,
      where: p.pedinte_id == ^pedinte_id,
      order_by: [desc: p.inserted_at]
    )
  end

  @doc "A chave publica ativa da Tekoa (aposentada nao assina)."
  def chave_ativa(tekoa_id) do
    from(k in TekoaKey,
      where: k.tekoa_id == ^tekoa_id,
      where: is_nil(k.aposentada_em),
      order_by: [desc: k.inserted_at],
      limit: 1
    )
  end
end
