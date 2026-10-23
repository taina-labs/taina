defmodule Ypy.PublicId do
  @moduledoc """
  Identificador publico dos recursos que nao sao enderecados por conteudo
  (Tekoa, ava, concessao): 12 caracteres de um alfabeto URL-safe de 64
  simbolos, 72 bits de aleatoriedade. Nao revela o id surrogate do banco nem
  a ordem de criacao; para id publico ordenavel por tempo existe o TID
  (RFC_006, secao 12), nao este.

  E um `Ecto.Type`:

      field :public_id, Ypy.PublicId, autogenerate: true
  """

  use Ecto.Type

  @alphabet ~c"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"
  @chars MapSet.new(@alphabet)
  @size 12
  @entropy_bytes 9

  @doc "Gera um id publico de 12 caracteres."
  def generate do
    for <<c::6 <- :crypto.strong_rand_bytes(@entropy_bytes)>>, into: "" do
      <<Enum.fetch!(@alphabet, c)>>
    end
  end

  @doc "Verifica a forma: exatamente 12 caracteres do alfabeto URL-safe."
  def valid?(id) when is_binary(id) and byte_size(id) == @size do
    id |> String.to_charlist() |> Enum.all?(&MapSet.member?(@chars, &1))
  end

  def valid?(_), do: false

  @impl true
  def type, do: :string

  @impl true
  def cast(id) when is_binary(id) do
    if valid?(id), do: {:ok, id}, else: :error
  end

  def cast(_), do: :error

  @impl true
  def load(id) when is_binary(id), do: {:ok, id}

  @impl true
  def dump(id) when is_binary(id), do: {:ok, id}
  def dump(_), do: :error

  @impl true
  def autogenerate, do: generate()
end
