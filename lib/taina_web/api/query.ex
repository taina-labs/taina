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

  @type cursor :: String.t() | nil
  @type direction :: :asc | :desc
  @type offset_value :: integer()
  @type options :: keyword()
  @type parameters :: map()
  @type sort_field :: :name | :date | :size
  @type sort_spec :: {sort_field(), direction()}

  @doc "O cursor `after` das listas por rkey (o manifesto de backup), do mais antigo para o mais novo."
  @spec after_cursor(parameters()) :: cursor()
  def after_cursor(params) do
    case params["after"] do
      <<_::binary-size(1), _::binary>> = value -> value
      _ -> nil
    end
  end

  @doc "O cursor opaco de uma lista paginada por keyset."
  @spec cursor(parameters()) :: cursor()
  def cursor(params) do
    case params["cursor"] do
      <<_::binary-size(1), _::binary>> = value -> value
      _ -> nil
    end
  end

  @doc "O offset como `next_cursor`, ou nil no fim da lista."
  @spec encode_offset(nil | offset_value()) :: cursor()
  def encode_offset(nil), do: nil
  def encode_offset(offset) when is_integer(offset), do: Integer.to_string(offset)

  @doc "O limite de pagina, entre 1 e o teto."
  @spec limit(parameters(), options()) :: pos_integer()
  def limit(params, opts \\ []) do
    default = Keyword.get(opts, :default, @default_limit)
    max = Keyword.get(opts, :max, @max_limit)

    case integer(params["limit"]) do
      nil -> default
      n -> n |> max(1) |> min(max)
    end
  end

  @doc "O offset de uma lista paginada por offset: o `cursor` e decimal."
  @spec offset(parameters()) :: non_neg_integer()
  def offset(params) do
    case integer(params["cursor"]) do
      n when is_integer(n) and n >= 0 -> n
      _ -> 0
    end
  end

  @doc """
  O par `{campo, direcao}` de `sort` (`name|date|size` mais `asc|desc`), ou nil
  quando ausente ou invalido. Sem direcao, sobe.
  """
  @spec sort(parameters()) :: sort_spec() | nil
  def sort(params) do
    case params["sort"] do
      value when is_binary(value) -> parse_sort(value)
      _ -> nil
    end
  end

  defp integer(nil), do: nil
  defp integer(value) when is_integer(value), do: value

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp integer(_), do: nil

  defp parse_sort(value) do
    [field | rest] = String.split(value, ["_", ":"], parts: 2)

    with {:ok, field} <- sort_field(field), {:ok, dir} <- sort_dir(rest) do
      {field, dir}
    else
      :error -> nil
    end
  end

  defp sort_dir([]), do: {:ok, :asc}
  defp sort_dir(["asc"]), do: {:ok, :asc}
  defp sort_dir(["desc"]), do: {:ok, :desc}
  defp sort_dir(_), do: :error

  defp sort_field("name"), do: {:ok, :name}
  defp sort_field("date"), do: {:ok, :date}
  defp sort_field("size"), do: {:ok, :size}
  defp sort_field(_), do: :error
end
