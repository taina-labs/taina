defmodule Ypy.Maraca.Policy do
  @moduledoc """
  A politica social pura do Maraca: zonas, papeis, a regra de leitura e os
  prazos de convite e reset.

  Tudo roda sobre dado plano, sem banco, sem processo e sem relogio: o agora
  entra como argumento e as concessoes chegam como a lista de fatos ativos.
  Esta e a funcao de leitura que a RFC_003 D2 subiu para o kernel, e o
  zelador nao tem atalho nela: nenhuma regra consulta o papel.
  """

  @zonas [:casa, :praca]
  @papeis [:zelador, :morador]
  @invite_max_age_seconds 2 * 24 * 60 * 60
  @reset_max_age_seconds 30 * 60

  @doc "As duas zonas de todo conteudo (RFC_003 D2)."
  @spec zonas() :: [:casa | :praca]
  def zonas, do: @zonas

  @doc "Os dois papeis de uma Tekoa."
  @spec papeis() :: [:zelador | :morador]
  def papeis, do: @papeis

  @doc """
  O papel de quem cuida da maquina (disco, backup, convites): zero
  autoridade sobre dados e zero poder social unilateral.
  """
  @spec zelador?(atom()) :: boolean()
  def zelador?(:zelador), do: true
  def zelador?(_), do: false

  @doc "O papel de membro comum, sem dever de maquina. Um zelador e membro da comunidade, mas seu papel e outro."
  @spec morador?(atom()) :: boolean()
  def morador?(:morador), do: true
  def morador?(_), do: false

  @doc """
  A regra de leitura das duas zonas (RFC_003 D2): praca OU dono OU concessao.

  `zona` e a zona do recurso, `leitor_id` e `dono_id` identificam quem le e
  quem e dono, `recurso` e o id publico do item e `concessoes` sao as
  concessoes ativas, cada uma um mapa com `leitor_id` e `recurso`. Ler a casa
  de alguem exige concessao explicita do dono, e vale para o zelador como
  para qualquer morador; a praca ninguem pede para ler.
  """
  @spec can_read?(:casa | :praca, term(), term(), term(), [map()]) :: boolean()
  def can_read?(zona, leitor_id, dono_id, recurso, concessoes) when zona in @zonas and is_list(concessoes) do
    zona == :praca or leitor_id == dono_id or
      Enum.any?(concessoes, &concedido?(&1, leitor_id, recurso))
  end

  def can_read?(_zona, _leitor_id, _dono_id, _recurso, _concessoes), do: false

  defp concedido?(%{leitor_id: leitor_id, recurso: recurso}, leitor_id, recurso), do: true
  defp concedido?(_concessao, _leitor_id, _recurso), do: false

  @doc "Quanto tempo um convite vale, em segundos, contado da emissao."
  @spec invite_max_age_seconds() :: pos_integer()
  def invite_max_age_seconds, do: @invite_max_age_seconds

  @doc "Quanto tempo um link de redefinicao de senha vale, em segundos, contado da emissao."
  @spec reset_max_age_seconds() :: pos_integer()
  def reset_max_age_seconds, do: @reset_max_age_seconds

  @doc "Um convite expirou? nil (nunca emitido) ja nasce vencido."
  @spec invite_expired?(DateTime.t() | nil, DateTime.t()) :: boolean()
  def invite_expired?(sent_at, now), do: expired?(sent_at, now, @invite_max_age_seconds)

  @doc "Um link de redefinicao de senha expirou?"
  @spec reset_expired?(DateTime.t() | nil, DateTime.t()) :: boolean()
  def reset_expired?(sent_at, now), do: expired?(sent_at, now, @reset_max_age_seconds)

  @doc "Um token expirou: faltou data de emissao, ou o agora passou da emissao mais o maximo."
  @spec expired?(DateTime.t() | nil, DateTime.t(), pos_integer()) :: boolean()
  def expired?(nil, _now, _max_age_seconds), do: true

  def expired?(%DateTime{} = sent_at, %DateTime{} = now, max_age_seconds),
    do: DateTime.diff(now, sent_at) > max_age_seconds
end
