defmodule Taina.AccountOperator do
  @moduledoc "Release-safe account recovery operation."
  alias Taina.Maraca
  alias Taina.Repo
  alias Ypy.Maraca.Ava

  def reset_password(username, password) when is_binary(username) and is_binary(password) do
    case Maraca.get_tekoa() do
      {:ok, tekoa} -> reset_password_in_tekoa(tekoa, normalize_username(username), password)
      nil -> {:error, :not_found}
      {:error, :not_bootstrapped} = error -> error
      error -> error
    end
  end

  defp find(tekoa, username) do
    Repo.with_tekoa(tekoa.public_id, fn ->
      case Repo.get_by(Ava, username: username, tekoa_id: tekoa.id) do
        %Ava{} = ava -> {:ok, ava}
        nil -> {:error, :not_found}
      end
    end)
  end

  defp normalize_username(input), do: input |> Ypy.Handle.normalize() |> String.split("@", parts: 2) |> List.first()

  defp reset_password_error(nil), do: {:error, :not_found}
  defp reset_password_error({:error, :not_found}), do: {:error, :not_found}
  defp reset_password_error({:error, :not_bootstrapped} = error), do: error
  defp reset_password_error({:error, %Ecto.Changeset{}}), do: {:error, :invalid_password}
  defp reset_password_error(error), do: error

  defp reset_password_in_tekoa(tekoa, username, password) do
    with {:ok, ava} <- find(tekoa, username),
         {:ok, _} <- update(tekoa, ava, password),
         :ok <- Maraca.revoke_other_devices(Taina.Scope.new(ava, tekoa), except: nil) do
      {:ok, ava}
    else
      error -> reset_password_error(error)
    end
  end

  defp update(tekoa, ava, password),
    do: Repo.with_tekoa(tekoa.public_id, fn -> Repo.update(Ava.reset_changeset(ava, %{password: password})) end)
end
