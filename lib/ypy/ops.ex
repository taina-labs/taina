defmodule Ypy.Ops do
  @moduledoc """
  Contrato de driver de host. Impls vivem no produto (box: compose;
  appliance: systemd/nix). Codigos de saida: 0 ok, 1 falha de dominio, 2 uso;
  o driver soma 3 (driver/ambiente).
  """

  alias Ypy.Ops.RunOnce

  @typedoc "A impl do produto."
  @type t :: struct()

  @typedoc "Falha de qualquer operacao de host."
  @type primitive_error :: {:error, term()}

  @typedoc "Onde os dados da Tekoa vivem."
  @type data_dir :: {:ok, String.t() | {:volume, String.t()}} | primitive_error

  @typedoc "Saude do deploy."
  @type health :: {:ok, :healthy | :degraded} | primitive_error

  @doc "O diretorio de dados do host."
  @callback data_dir() :: data_dir()

  @doc "Roda um verbo unico do produto (ex.: `migrate`, `backup`)."
  @callback run_once(RunOnce.t()) :: :ok | primitive_error

  @doc "Sobe o deploy."
  @callback up() :: :ok | primitive_error

  @doc "Derruba o deploy."
  @callback down() :: :ok | primitive_error

  @doc "Reinicia o deploy."
  @callback restart() :: :ok | primitive_error

  @doc "Traz a imagem de `nil` (ultima) ou da versao dada."
  @callback pull(nil | String.t()) :: :ok | primitive_error

  @doc "Mostra os logs do deploy."
  @callback logs(keyword()) :: :ok | primitive_error

  @doc "A saude do deploy."
  @callback health() :: health()

  @doc "O driver roda interativo (o mesmo terminal de quem chamou)?"
  @callback interactive?() :: boolean()

  @doc """
  O driver e dono do ciclo de vida do processo (systemd/nix sao; compose
  interativo nao e)? Quando e, o produto nao emprende cuidado proprio.
  """
  @callback owns_lifecycle?() :: boolean()
end
