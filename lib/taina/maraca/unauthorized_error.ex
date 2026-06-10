defmodule Taina.Maraca.UnauthorizedError do
  @moduledoc """
  Levantada por `Taina.Maraca.authorize!/4` quando o acesso é negado.
  """

  defexception [:message, plug_status: 403]

  @impl true
  def exception(opts) do
    ava = Keyword.get(opts, :ava)
    action = Keyword.get(opts, :action)
    resource_type = Keyword.get(opts, :resource_type)
    resource_id = Keyword.get(opts, :resource_id)

    %__MODULE__{
      message:
        "não autorizado: ava=#{ava && ava.public_id} action=#{action} " <>
          "resource=#{resource_type}/#{resource_id}"
    }
  end
end
