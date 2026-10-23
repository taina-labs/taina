defmodule Ypy.Maraca.Credentials do
  @moduledoc """
  Senhas: hash e verificacao com bcrypt (RFC_006 D10).

  O kernel carrega a matematica (o substantivo e a invariante); os fluxos de
  login, convite, reset e rate limit ficam no produto. A comparacao constante
  no tempo e propriedade do `bcrypt_elixir`.
  """

  @doc """
  Hash bcrypt da senha. As opcoes vao direto ao `bcrypt_elixir`
  (ex.: `log_rounds: 4` em testes).
  """
  def hash(password, opts \\ []) when is_binary(password) do
    Bcrypt.hash_pwd_salt(password, opts)
  end

  @doc "Confere a senha contra o hash armazenado. Senha errada ou hash malformado devolvem false."
  def valid_password?(password, hash) when is_binary(password) and is_binary(hash) do
    Bcrypt.verify_pass(password, hash)
  end
end
