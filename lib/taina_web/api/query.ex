defmodule TainaWeb.API.Query do
  @moduledoc """
  Os parametros de lista, parseados leniente na borda (RFC_005 secao 7):
  `limit` (padrao 50, teto 100), `cursor` e `sort`. Valor invalido cai no
  padrao, nunca levanta.

  Listas por keyset (fotos, lixeira, arquivos) leem o cursor opaco; listas por
  offset (conteudo de pasta, mural) leem um offset decimal e o devolvem em
  string, porque `next_cursor` e sempre string ou null.
  """

  @default_limit 50
  @max_limit 100

  @doc "O limite de pagina, entre 1 e o teto."
  @spec limit(map()) :: pos_integer()
  def limit(params) do
    case integer(params["limit"]) do
      nil -> @default_limit
      n -> n |> max(1) |> min(@max_limit)
    end
  end

  @doc "O offset de uma lista paginada por offset: o `cursor` e decimal."
  @spec offset(map()) :: non_neg_integer()
  def offset(params) do
    case integer(params["cursor"]) do
      n when is_integer(n) and n >= 0 -> n
      _ -> 0
    end
  end

  @doc "O cursor opaco de uma lista paginada por keyset."
  @spec cursor(map()) :: String.t() | nil
  def cursor(params) do
    case params["cursor"] do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  @doc """
  O par `{campo, direcao}` de `sort` (`name|date|size` mais `asc|desc`), ou nil
  quando ausente ou invalido. Sem direcao, sobe.
  """
  @spec sort(map()) :: {:name | :date | :size, :asc | :desc} | nil
  def sort(params) do
    case params["sort"] do
      value when is_binary(value) -> parse_sort(value)
      _ -> nil
    end
  end

  @doc "O offset como `next_cursor`, ou nil no fim da lista."
  @spec encode_offset(nil | integer()) :: String.t() | nil
  def encode_offset(nil), do: nil
  def encode_offset(offset) when is_integer(offset), do: Integer.to_string(offset)

  defp parse_sort(value) do
    [field | rest] = String.split(value, ["_", ":"], parts: 2)

    with {:ok, field} <- sort_field(field), {:ok, dir} <- sort_dir(rest) do
      {field, dir}
    else
      :error -> nil
    end
  end

  defp sort_field("name"), do: {:ok, :name}
  defp sort_field("date"), do: {:ok, :date}
  defp sort_field("size"), do: {:ok, :size}
  defp sort_field(_), do: :error

  defp sort_dir([]), do: {:ok, :asc}
  defp sort_dir(["asc"]), do: {:ok, :asc}
  defp sort_dir(["desc"]), do: {:ok, :desc}
  defp sort_dir(_), do: :error

  defp integer(nil), do: nil
  defp integer(value) when is_integer(value), do: value

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp integer(_), do: nil
end
