defmodule Taina.AccountOperator do
  @moduledoc "Release-safe account recovery operation."
  alias Taina.Maraca
  alias Taina.Repo
  alias Ypy.Maraca.Ava

  def reset_password(username, password) when is_binary(username) and is_binary(password) do
    with {:ok, tekoa} <- Maraca.get_tekoa(),
         username = normalize_username(username),
         {:ok, ava} <- find(tekoa, username),
         {:ok, _} <- update(tekoa, ava, password),
         :ok <- Maraca.revoke_other_devices(Taina.Scope.new(ava, tekoa), except: nil) do
      {:ok, ava}
    else
      nil -> {:error, :not_found}
      {:error, :not_bootstrapped} -> {:error, :not_bootstrapped}
      {:error, %Ecto.Changeset{}} -> {:error, :invalid_password}
      error -> error
    end
  end

  defp find(tekoa, username),
    do: Repo.with_tekoa(tekoa.public_id, fn -> {:ok, Repo.get_by(Ava, username: username, tekoa_id: tekoa.id)} end)

  defp update(tekoa, ava, password),
    do: Repo.with_tekoa(tekoa.public_id, fn -> Repo.update(Ava.reset_changeset(ava, %{password: password})) end)

  defp normalize_username(input), do: input |> Ypy.Handle.normalize() |> String.split("@", parts: 2) |> List.first()
end
