defmodule TainaWeb.MuralText do
  @moduledoc """
  As frases do mural, núcleo puro (docs/web-revamp-spec.md 6.1/6.4): o evento
  e os nomes já resolvidos entram, a frase sai.

  A mesma frase é lida em dois lugares: no Mural inteiro (`MuralLive`) e na
  linha "Mural" do hub (`HomeLive`), que mostra só o último ato. Nenhuma
  consulta aqui: quem lê do banco resolve os nomes do payload antes de chamar
  `sentence/2`.
  """

  use Gettext, backend: TainaWeb.Gettext

  import TainaWeb.CoreComponents, only: [format_bytes: 1]

  alias Ypy.Mural.Entry

  require Logger

  @doc """
  Frase simples de um ato registrado no mural, sem IDs e sem jargão.

  O `payload` do evento carrega o ator (o `public_id`); `names` é o mapa
  `public_id -> nome social` que a tela montou. Ator ausente (ato do sistema)
  vira "O sistema".

  Se um ato não cabe numa frase, o problema é o `type`, não a frase: o
  fallback mantém a linha no ar e o log marca o tipo para alguém escrever a
  frase dele.
  """
  def resource_refs(events) when is_list(events) do
    events
    |> Enum.map(fn event -> {event.payload["collection"], event.payload["rkey"]} end)
    |> Enum.filter(fn
      {type, rkey} when type in ["ypy.file.v0", "ypy.folder.v0"] and is_binary(rkey) -> true
      _other -> false
    end)
    |> Enum.uniq()
  end

  def sentence(%Entry{tipo: "invite_created"} = event, names) do
    if event.payload["role"] == "zelador" do
      gettext("%{actor} convidou uma nova pessoa para cuidar da máquina.", actor: actor_label(event, names))
    else
      gettext("%{actor} convidou uma nova pessoa para a comunidade.", actor: actor_label(event, names))
    end
  end

  # O papel do convite, gravado no aceite, decide a frase: quem entra para
  # cuidar da máquina merece a frase certa na hora da concessão. Eventos
  # antigos (payload vazio) caem na frase genérica.
  def sentence(%Entry{tipo: "invite_accepted", payload: %{"role" => "zelador"}} = event, names),
    do: gettext("%{actor} entrou na comunidade para cuidar da máquina.", actor: actor_label(event, names))

  def sentence(%Entry{tipo: "invite_accepted"} = event, names),
    do: gettext("%{actor} entrou na comunidade.", actor: actor_label(event, names))

  def sentence(%Entry{tipo: "invite_revoked", payload: %{"role" => "zelador"}} = event, names),
    do: gettext("%{actor} revogou um convite para cuidar da máquina.", actor: actor_label(event, names))

  def sentence(%Entry{tipo: "invite_revoked"} = event, names),
    do: gettext("%{actor} revogou um convite.", actor: actor_label(event, names))

  # O zelador não vê nem define a senha nova, só gera o link: o ato é dele,
  # o destino é o membro nomeado no payload.
  def sentence(%Entry{tipo: "reset_link_created", payload: %{"member" => member}} = event, names) when is_binary(member),
    do: gettext("%{actor} gerou um link de nova senha para %{member}.", actor: actor_label(event, names), member: member)

  def sentence(%Entry{tipo: "reset_link_created"} = event, names),
    do: gettext("%{actor} gerou um link de nova senha para um membro da comunidade.", actor: actor_label(event, names))

  def sentence(%Entry{tipo: "member_deactivated"} = event, names) do
    case event.payload["member"] do
      nil -> gettext("%{actor} desativou uma conta.", actor: actor_label(event, names))
      member -> gettext("%{actor} desativou a conta de %{member}.", actor: actor_label(event, names), member: member)
    end
  end

  def sentence(%Entry{tipo: "member_reactivated", payload: %{"member" => member}} = event, names) when is_binary(member),
    do: gettext("%{actor} reativou a conta de %{member}.", actor: actor_label(event, names), member: member)

  def sentence(%Entry{tipo: "member_reactivated"} = event, names),
    do: gettext("%{actor} reativou uma conta.", actor: actor_label(event, names))

  def sentence(%Entry{tipo: "quota_changed", payload: %{"from" => from, "to" => to}} = event, names)
      when is_integer(from) do
    gettext("%{actor} mudou o limite de armazenamento de %{from} para %{to}.",
      actor: actor_label(event, names),
      from: format_bytes(from),
      to: format_bytes(to)
    )
  end

  def sentence(%Entry{tipo: "quota_changed", payload: %{"to" => to}} = event, names),
    do:
      gettext("%{actor} mudou o limite de armazenamento para %{to}.",
        actor: actor_label(event, names),
        to: format_bytes(to)
      )

  def sentence(%Entry{tipo: "quota_changed"} = event, names),
    do: gettext("%{actor} mudou o limite de armazenamento.", actor: actor_label(event, names))

  # Verbos do kernel na cadeia: o payload deles carrega o ator e a coleção
  # (o rkey do recurso fica no payload para a auditoria, não para a frase),
  # então a frase nomeia quem fez e o que fez, sem o nome do recurso.
  def sentence(%Entry{tipo: "put", payload: %{"collection" => "ypy.folder.v0"}} = event, names) do
    case resource_name(event, names) do
      name when is_binary(name) ->
        gettext("%{actor} guardou a pasta %{resource} na caixa.", actor: actor_label(event, names), resource: name)

      _missing ->
        gettext("%{actor} criou uma pasta.", actor: actor_label(event, names))
    end
  end

  def sentence(%Entry{tipo: "put"} = event, names) do
    case resource_name(event, names) do
      name when is_binary(name) ->
        gettext("%{actor} guardou %{resource} na caixa.", actor: actor_label(event, names), resource: name)

      _missing ->
        gettext("%{actor} guardou um arquivo na caixa.", actor: actor_label(event, names))
    end
  end

  def sentence(%Entry{tipo: "publicar", payload: %{"collection" => "ypy.folder.v0"}} = event, names) do
    case resource_name(event, names) do
      name when is_binary(name) ->
        gettext("%{actor} publicou a pasta %{resource} na praça.", actor: actor_label(event, names), resource: name)

      _missing ->
        gettext("%{actor} publicou uma pasta na praça.", actor: actor_label(event, names))
    end
  end

  def sentence(%Entry{tipo: "publicar"} = event, names) do
    case resource_name(event, names) do
      name when is_binary(name) ->
        gettext("%{actor} publicou %{resource} na praça.", actor: actor_label(event, names), resource: name)

      _missing ->
        gettext("%{actor} publicou um arquivo na praça.", actor: actor_label(event, names))
    end
  end

  def sentence(%Entry{tipo: "tirar_da_praca", payload: %{"collection" => "ypy.folder.v0"}} = event, names),
    do: gettext("%{actor} tirou uma pasta da praça.", actor: actor_label(event, names))

  def sentence(%Entry{tipo: "tirar_da_praca"} = event, names),
    do: gettext("%{actor} tirou um arquivo da praça.", actor: actor_label(event, names))

  def sentence(%Entry{tipo: "apagar", payload: %{"collection" => "ypy.folder.v0"}} = event, names),
    do: gettext("%{actor} mandou uma pasta para a lixeira.", actor: actor_label(event, names))

  def sentence(%Entry{tipo: "apagar"} = event, names),
    do: gettext("%{actor} mandou um arquivo para a lixeira.", actor: actor_label(event, names))

  def sentence(%Entry{tipo: "restaurar"} = event, names),
    do: gettext("%{actor} tirou um arquivo da lixeira.", actor: actor_label(event, names))

  def sentence(%Entry{tipo: "mover"} = event, names),
    do: gettext("%{actor} moveu um arquivo de pasta.", actor: actor_label(event, names))

  def sentence(%Entry{tipo: "renomear", payload: %{"collection" => "ypy.folder.v0"}} = event, names),
    do: gettext("%{actor} renomeou uma pasta.", actor: actor_label(event, names))

  def sentence(%Entry{tipo: "renomear"} = event, names),
    do: gettext("%{actor} renomeou um arquivo.", actor: actor_label(event, names))

  # A concessao nasce de um pedido aprovado ou do proprio dono abrindo a
  # casa; o "leitor" (public_id) no payload para a auditoria.
  def sentence(%Entry{tipo: "concessao"} = event, names),
    do: gettext("%{actor} abriu a sua casa para a leitura de um morador.", actor: actor_label(event, names))

  def sentence(%Entry{tipo: "revogar"} = event, names),
    do: gettext("%{actor} tirou a leitura que tinha aberto.", actor: actor_label(event, names))

  def sentence(%Entry{tipo: "mudar_papel", payload: %{"papel" => "zelador"}} = event, names),
    do: gettext("%{actor} deu a um morador o cuidado da máquina.", actor: actor_label(event, names))

  def sentence(%Entry{tipo: "mudar_papel"} = event, names),
    do: gettext("%{actor} tirou de um morador o cuidado da máquina.", actor: actor_label(event, names))

  # Entrada de um tipo que o mural ainda não conhece (inclui os tipos do
  # kernel: concessao, publicar, put...): o mural e append-only e nao pode
  # derrubar por causa de uma frase faltando.
  def sentence(%Entry{tipo: tipo} = event, names) do
    Logger.warning("mural: entrada sem frase mapeada", event_type: tipo, event_id: event.id)

    gettext("%{actor} fez um ato registrado na comunidade.", actor: actor_label(event, names))
  end

  defp actor_label(event, names) do
    actors = Map.get(names, :actors, names)
    Map.get(actors, event.payload["actor"], gettext("O sistema"))
  end

  defp resource_name(event, names) do
    resources = Map.get(names, :resources, %{})
    Map.get(resources, {event.payload["collection"], event.payload["rkey"]})
  end
end
