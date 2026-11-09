defmodule AddSigningKeyToMaracaMural do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:maraca_mural) do
      add :signing_key, :binary
    end
  end
end
