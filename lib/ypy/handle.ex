defmodule Ypy.Handle do
  @moduledoc """
  O handle e o endereco social de quem age na Tekoa: `maria@tekoa.example.org`
  (RFC_003 D9). A regra e restrita de proposito: o handle precisa poder virar
  endereco de federacao (`nome@tekoa`) sem ambiguidade.

  - `nome`: minusculas, digitos, ponto, hifen e underline, sem espacos;
  - `tekoa`: dominio DNS valido (rotulos de 1 a 63 caracteres, hifen apenas
    no meio, um ou mais rotulos).

  O limite total e de 253 bytes, o limite de um dominio. A normalizacao
  (`normalize/1`) e sempre explicita: trim e minusculas, nada alem disso.
  `parse/1` e `valid?/1` aceitam apenas a forma canonica.
  """

  @max_length 253
  @nome ~r/^[a-z0-9._-]+$/
  @label ~r/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/

  @doc "Normaliza o handle cru: trim e minusculas, sem validar."
  def normalize(handle) when is_binary(handle) do
    handle |> String.trim() |> String.downcase()
  end

  @doc """
  Valida e separa as partes de um handle na forma canonica.

      iex> Ypy.Handle.parse("maria@tekoa.example.org")
      {:ok, %{nome: "maria", tekoa: "tekoa.example.org"}}

  Devolve `{:error, :invalid}` para forma invalida ou nao canonica
  (normal antes de parse).
  """
  def parse(handle) when is_binary(handle) and byte_size(handle) <= @max_length do
    case String.split(handle, "@", parts: 2) do
      [nome, tekoa] -> parse_parts(nome, tekoa)
      _ -> {:error, :invalid}
    end
  end

  def parse(_), do: {:error, :invalid}

  @doc "Verifica se o handle e valido na forma canonica."
  def valid?(handle), do: match?({:ok, _}, parse(handle))

  @doc """
  Verifica se e um dominio de Tekoa valido (a parte depois do `@`).
  E a mesma gramatica que `Ypy.Did.from_domain/1` cobra.
  """
  def valid_domain?(domain) when is_binary(domain) and byte_size(domain) <= @max_length do
    domain != "" and Enum.all?(String.split(domain, "."), &valid_label?/1)
  end

  def valid_domain?(_), do: false

  defp parse_parts(nome, tekoa) do
    if Regex.match?(@nome, nome) and valid_domain?(tekoa) do
      {:ok, %{nome: nome, tekoa: tekoa}}
    else
      {:error, :invalid}
    end
  end

  defp valid_label?(label) do
    byte_size(label) <= 63 and Regex.match?(@label, label)
  end
end
