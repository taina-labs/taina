defmodule Ypy.KeyStore do
  @moduledoc """
  Guarda e usa a chave privada da Tekoa.

  A chave privada nunca sai do KeyStore: o kernel pede a assinatura pronta
  (o encadeamento do mural e quem a usa) e a chave publica derivada. Girar a
  chave e o `rotate/3`, e a chave aposentada fica no banco
  (`Ypy.Maraca.TekoaKey`), jamais sobrescrita em silencio.
  """

  alias Ypy.Maraca.Keys

  @typedoc "A impl do produto."
  @type t :: struct()

  @typedoc "Chave publica comprimida e chave privada."
  @type keypair :: Keys.keypair()

  @doc "Mintta um par novo."
  @callback generate(t()) :: {:ok, keypair()} | {:error, term()}

  @doc "Assina `payload` com a chave privada da Tekoa."
  @callback sign(t(), tekoa_id :: integer(), binary()) ::
              {:ok, binary()} | {:error, :not_found | term()}

  @doc "A chave publica comprimida da Tekoa."
  @callback fetch_public(t(), tekoa_id :: integer()) ::
              {:ok, binary()} | {:error, :not_found}

  @doc "Claims the key file during first-time initialization. Returns `:eexist` if another initializer already created it."
  @callback initialize(t(), tekoa_id :: integer(), keypair()) :: :ok | {:error, term()}

  @doc "Explicitly replaces the current key file atomically, or creates it if absent."
  @callback rotate(t(), tekoa_id :: integer(), keypair()) :: :ok | {:error, term()}
end
