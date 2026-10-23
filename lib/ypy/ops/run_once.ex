defmodule Ypy.Ops.RunOnce do
  @moduledoc """
  Um verbo unico a rodar no host: o `verb`, o `argv` dele, o ambiente, os
  volumes montados e se roda interativo. A forma e a do Pesque.
  """

  @enforce_keys [:verb]
  defstruct verb: nil, argv: [], env: %{}, mounts: %{}, interactive?: false

  @type t :: %__MODULE__{
          verb: String.t(),
          argv: [String.t()],
          env: %{String.t() => String.t()},
          mounts: %{String.t() => String.t()},
          interactive?: boolean()
        }
end
