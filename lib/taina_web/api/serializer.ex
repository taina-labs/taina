defmodule TainaWeb.API.Serializer do
  @moduledoc """
  As formas do fio que so o box conhece (RFC_005 secao 9): instancia, Tekoa,
  dispositivo, sessao, armazenamento, saude, pedido, concessao e alvo de acesso.

  Arquivo, pasta, pessoa e entrada do mural vem do kernel (`Ypy.Wire.File`,
  `Ypy.Wire.Ava`, `Ypy.Wire.Mural`), que e a fonte unica dessas formas: os
  controllers chamam o shape do kernel direto e este modulo nao os repete.
  """

  alias Taina.Maraca.DeviceToken
  alias Ypy.Maraca.Concessao
  alias Ypy.Maraca.Pedido
  alias Ypy.Maraca.Tekoa
  alias Ypy.Wire

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
  @spec session(String.t(), DeviceToken.t(), Ypy.Scope.t()) :: map()
  def session(token, %DeviceToken{} = device, scope) do
    %{
      "token" => token,
      "device" => device(device),
      "me" => Wire.Ava.json(scope.ava),
      "tekoa" => tekoa(scope.tekoa)
    }
  end

  @doc "Quem esta agindo: a pessoa, a Tekoa e o dispositivo da chamada."
  @spec me(Ypy.Scope.t(), nil | DeviceToken.t()) :: map()
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

  defp version do
    case Application.spec(:taina, :vsn) do
      nil -> nil
      vsn -> to_string(vsn)
    end
  end
end
