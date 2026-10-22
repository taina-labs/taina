defmodule TainaWeb.API.Serializer do
  @moduledoc """
  As formas do fio que so o box conhece (RFC_005 secao 9): instancia, Tekoa,
  dispositivo, sessao, armazenamento, saude, pedido, concessao e alvo de acesso.

  Arquivo, pasta, pessoa e entrada do mural tem a forma crua no kernel
  (`Ypy.Wire.File`, `Ypy.Wire.Ava`, `Ypy.Wire.Mural`), que e a fonte unica
  dessas formas. O arquivo do produto embala a forma do kernel com os campos
  do produto (`file/2`), sem repeti-los.
  """

  alias Taina.Maraca.DeviceToken
  alias Taina.Ybira
  alias Taina.Ybira.RenditionStatus
  alias Ypy.Maraca.Concessao
  alias Ypy.Maraca.Pedido
  alias Ypy.Maraca.Tekoa
  alias Ypy.Scope
  alias Ypy.Wire
  alias Ypy.Ybira.File

  @doc """
  O arquivo no fio do produto (contrato review 0.1.0, A): a forma do kernel
  (`Ypy.Wire.File.json/1`, que fica intacta) mais os campos do produto. A
  pasta pai vem resolvida pela regra de leitura, os metadados de foto
  (`taken_at`, dimensoes) e o estado da rendition vem do Jaci -- e valem para
  TODO endpoint que devolve arquivo, inclusive recentes, fotos e lixeira,
  onde o `folder` do kernel chegava sempre nulo.

  Um arquivo sozinho: tres leituras curtas (metadados, estado, pasta). Para
  lista, use `files/2`, que carrega tudo em lote.
  """
  @spec file(Scope.t(), File.t()) :: map()
  def file(%Scope{} = scope, %File{} = file) do
    {:ok, metadata} = Ybira.photo_metadata(scope, file)

    file
    |> Wire.File.json()
    |> Map.merge(%{
      "taken_at" => taken_at(metadata["taken_at"]),
      "width" => dimension(metadata["width"]),
      "height" => dimension(metadata["height"]),
      "rendition" => rendition(scope, file),
      "folder" => folder_rkey(scope, file)
    })
  end

  @doc """
  A pagina de arquivos no fio do produto: os mesmos mapas de `file/2`, com
  as leituras em lote. Uma consulta para os metadados de foto da pagina
  (`where file_id in ...`), uma para as pastas pai distintas; o estado da
  rendition sai dos metadados que ja vieram, sem reconsulta. Quem lista
  muitos arquivos (manifesto, lote, recentes, conteudo, fotos, linha do
  tempo, lixeira) paga tres consultas, nao tres por arquivo.
  """
  @spec files(Scope.t(), [File.t()]) :: [map()]
  def files(%Scope{} = scope, files) when is_list(files) do
    {:ok, metadata_by_file_id} = Ybira.photos_metadata(scope, Enum.map(files, & &1.id))
    {:ok, folder_rkeys} = Ybira.files_folder_rkeys(scope, files)

    Enum.map(files, fn file ->
      metadata = Map.get(metadata_by_file_id, file.id, %{})

      file
      |> Wire.File.json()
      |> Map.merge(%{
        "taken_at" => taken_at(metadata["taken_at"]),
        "width" => dimension(metadata["width"]),
        "height" => dimension(metadata["height"]),
        "rendition" => file.mime |> RenditionStatus.from_metadata(metadata) |> to_string(),
        "folder" => Map.get(folder_rkeys, file.id)
      })
    end)
  end

  @doc "A Tekoa no fio."
  @spec tekoa(Tekoa.t()) :: map()
  def tekoa(%Tekoa{} = tekoa) do
    %{
      "public_id" => tekoa.public_id,
      "name" => tekoa.name,
      "domain" => tekoa.domain,
      "storage_quota_bytes" => tekoa.storage_quota_bytes,
      "storage_used_bytes" => tekoa.storage_used_bytes,
      "created_at" => Wire.at(tekoa.inserted_at)
    }
  end

  @doc "A instancia: se a caixa ja foi criada, a Tekoa dela, e a versao do box."
  @spec instance(boolean(), nil | Tekoa.t()) :: map()
  def instance(bootstrapped?, tekoa) do
    %{"bootstrapped" => bootstrapped?, "tekoa" => tekoa_json(tekoa), "version" => version()}
  end

  @doc "O dispositivo no fio: sem o hash, jamais."
  @spec device(DeviceToken.t()) :: map()
  def device(%DeviceToken{} = device) do
    %{
      "public_id" => device.public_id,
      "name" => device.name,
      "last_used_at" => Wire.at(device.last_used_at),
      "revoked_at" => Wire.at(device.revoked_at),
      "created_at" => Wire.at(device.inserted_at)
    }
  end

  @doc "A sessao: o segredo cru volta uma unica vez, aqui."
  @spec session(String.t(), DeviceToken.t(), Scope.t()) :: map()
  def session(token, %DeviceToken{} = device, scope) do
    %{
      "token" => token,
      "device" => device(device),
      "me" => Wire.Ava.json(scope.ava),
      "tekoa" => tekoa(scope.tekoa)
    }
  end

  @doc "Quem esta agindo: a pessoa, a Tekoa e o dispositivo da chamada."
  @spec me(Scope.t(), nil | DeviceToken.t()) :: map()
  def me(scope, device) do
    %{
      "ava" => Wire.Ava.json(scope.ava),
      "tekoa" => tekoa(scope.tekoa),
      "device" => device_json(device)
    }
  end

  @doc """
  O retrato do armazenamento: os bytes, a cota, a quebra por tipo, as contagens
  e o lixo.
  """
  @spec storage(map(), map(), non_neg_integer(), non_neg_integer(), map()) :: map()
  def storage(%{used_bytes: used, quota_bytes: quota}, by_kind, files, photos, trash) do
    %{
      "used_bytes" => used,
      "quota_bytes" => quota,
      "by_kind" => by_kind_json(by_kind),
      "files" => files,
      "photos" => photos,
      "trash" => %{"count" => trash.count, "bytes" => trash.bytes}
    }
  end

  @doc "A saude da comunidade: armazenamento, jobs em espera e o ultimo backup."
  @spec saude(map(), map(), tuple()) :: map()
  def saude(storage_json, jobs, backup) do
    %{"storage" => storage_json, "jobs" => jobs, "backup" => backup_json(backup)}
  end

  @doc "O pedido de acesso no fio, com as pontas (pedinte, dono) quando vieram preload."
  @spec pedido(Pedido.t()) :: map()
  def pedido(%Pedido{} = pedido) do
    %{
      "public_id" => pedido.public_id,
      "tipo" => pedido.tipo,
      "recurso" => pedido.recurso,
      "motivo" => pedido.motivo,
      "status" => to_string(pedido.status),
      "decidido_em" => Wire.at(pedido.decidido_em),
      "created_at" => Wire.at(pedido.inserted_at),
      "pedinte" => ava_json(pedido.pedinte),
      "dono" => ava_json(pedido.dono)
    }
  end

  @doc "A concessao no fio, com as pontas (leitor, dono) quando vieram preload."
  @spec concessao(Concessao.t()) :: map()
  def concessao(%Concessao{} = concessao) do
    %{
      "public_id" => concessao.public_id,
      "tipo" => concessao.tipo,
      "recurso" => concessao.recurso,
      "concedida_em" => Wire.at(concessao.concedida_em),
      "revogada_em" => Wire.at(concessao.revogada_em),
      "created_at" => Wire.at(concessao.inserted_at),
      "leitor" => ava_json(concessao.leitor),
      "dono" => ava_json(concessao.dono)
    }
  end

  @doc "O alvo de um pedido de acesso: o dono resolvido, o rkey e o nome."
  @spec access_target(map()) :: map()
  def access_target(%{owner: owner, rkey: rkey, nome: nome}) do
    %{"owner" => Wire.Ava.json(owner), "rkey" => rkey, "name" => nome}
  end

  defp tekoa_json(nil), do: nil
  defp tekoa_json(%Tekoa{} = tekoa), do: tekoa(tekoa)

  defp device_json(nil), do: nil
  defp device_json(%DeviceToken{} = device), do: device(device)

  defp by_kind_json(%{photos: photos, videos: videos, documents: documents, others: others}) do
    %{"photos" => photos, "videos" => videos, "documents" => documents, "others" => others}
  end

  defp backup_json({:ok, %{at: at, bytes: bytes}}), do: %{"at" => Wire.at(at), "bytes" => bytes}
  defp backup_json(_error), do: %{"at" => nil, "bytes" => nil}

  defp ava_json(%Ypy.Maraca.Ava{} = ava), do: Wire.Ava.json(ava)
  defp ava_json(_not_loaded), do: nil

  # A pasta pai resolvida pela regra de leitura (a mesma que autoriza a
  # leitura do arquivo): null quando ele esta solto na raiz, quando a pasta
  # ja foi para a lixeira ou quando a casa dela nao e legivel.
  defp folder_rkey(scope, file) do
    case Ybira.file_folder_rkey(scope, file) do
      {:ok, folder_rkey} -> folder_rkey
      _error -> nil
    end
  end

  # O estado da rendition, do dono dela no produto (`RenditionStatus`, a
  # mesma leitura que o endpoint de miniatura usa).
  defp rendition(scope, file), do: scope |> RenditionStatus.status(file) |> to_string()

  # A data de captura (EXIF) em UTC com `Z`, segundo truncado. Sem data, ou
  # com data que nao parseia, null (parse leniente, nunca levanta).
  defp taken_at(nil), do: nil
  defp taken_at(%DateTime{} = dt), do: wire_at(dt)
  defp taken_at(%NaiveDateTime{} = ndt), do: wire_at(DateTime.from_naive!(ndt, "Etc/UTC"))

  defp taken_at(value) when is_binary(value) do
    case parse_datetime(value) do
      {:ok, dt} -> wire_at(dt)
      :error -> nil
    end
  end

  defp taken_at(_other), do: nil

  # O fio guarda a data do EXIF sem fuso (ISO8601 cru do worker); com fuso
  # tambem passa, normalizado para UTC.
  defp parse_datetime(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} ->
        {:ok, dt}

      _ ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, ndt} -> {:ok, DateTime.from_naive!(ndt, "Etc/UTC")}
          _error -> :error
        end
    end
  end

  defp wire_at(dt), do: dt |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  defp dimension(value) when is_integer(value), do: value
  defp dimension(_other), do: nil

  defp version do
    case Application.spec(:taina, :vsn) do
      nil -> nil
      vsn -> to_string(vsn)
    end
  end
end
