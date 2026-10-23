defmodule Ypy.Did do
  @moduledoc """
  Identidade da Tekoa: `did:web` derivado do dominio da comunidade, sem PLC
  (RFC_006 D8). Mintar em `did:plc` escreveria num ledger publico estrangeiro
  no nascimento da Tekoa; `did:web` se resolve pelo proprio dominio, que serve
  `/.well-known/did.json` montado por `document/2`.

  Porta nao-padrao segue a especificacao did:web: os dois pontos viram `%3A`
  (`did:web:tekoa.example.org%3A8443`).
  """

  alias Ypy.Handle

  @port ~r/^[0-9]+$/

  @doc """
  Deriva o did:web do dominio da Tekoa.

      iex> Ypy.Did.from_domain("tekoa.example.org")
      "did:web:tekoa.example.org"

  Minusculas sao impostas. Dominio invalido levanta ArgumentError.
  """
  def from_domain(domain) when is_binary(domain) do
    {host, port} = split_port(domain)
    host = String.downcase(host)

    if not Handle.valid_domain?(host) or not valid_port?(port) do
      raise ArgumentError, "invalid tekoa domain: #{inspect(domain)}"
    end

    "did:web:" <> host <> encode_port(port)
  end

  @doc "O dominio (com a porta, quando houver) de um did:web da Tekoa."
  def domain("did:web:" <> rest) when is_binary(rest) do
    URI.decode(rest)
  end

  @doc """
  Monta o documento DID da Tekoa: `did` e o did:web derivado e a chave e a
  publica da Tekoa em multibase Multikey, a mesma que assina a cadeia.
  O produto serve o resultado em `/.well-known/did.json`.
  """
  def document("did:web:" <> _ = did, public_key_multibase) when is_binary(public_key_multibase) do
    method_id = did <> "#tekoa"

    %{
      "@context" => [
        "https://www.w3.org/ns/did/v1",
        "https://w3id.org/security/multikey/v1",
        "https://w3id.org/security/suites/secp256k1-2019/v1"
      ],
      "id" => did,
      "authentication" => [method_id],
      "verificationMethod" => [
        %{
          "id" => method_id,
          "type" => "Multikey",
          "controller" => did,
          "publicKeyMultibase" => public_key_multibase
        }
      ]
    }
  end

  defp split_port(domain) do
    case String.split(domain, ":", parts: 2) do
      [host, port] -> {host, port}
      [host] -> {host, nil}
    end
  end

  defp valid_port?(nil), do: true
  defp valid_port?(port), do: Regex.match?(@port, port) and String.to_integer(port) in 1..65_535

  defp encode_port(nil), do: ""
  defp encode_port(port), do: "%3A" <> port
end
