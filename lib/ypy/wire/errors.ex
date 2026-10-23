defmodule Ypy.Wire.Errors do
  @moduledoc """
  O vocabulario de erros do fio (RFC_005 secao 6): todo motivo que os
  contextos podem devolver, mapeado para o status HTTP e o code do envelope
  `{"error": {"code", "message", "details?"}}`.

  O code e a palavra estavel do cliente e e sempre o proprio atomo em
  string; o que distingue um motivo do outro e o status. Os nao-obvios da
  tabela: `:storage_quota_exceeded` e 409 (a comunidade encheu), e
  `:account_deactivated` e 403 (401 convidaria o cliente a repedir
  credenciais em laco). Conflito de estado e 409, entrada malformada e 422.

  Um `%Ecto.Changeset{}` vira 422 `validation_failed`, com as mensagens
  pt-BR deles como details. Os erros tagged dos contextos (`{:payload_invalido,
  erros}` e o par de indice e motivo da cadeia) abrem o par antes daqui: o
  tag e o code, a cauda sao os details. Motivo sem mapeamento responde 500
  `internal_error`, e o motivo em si vai para o log, nunca para o corpo.
  """

  @fallback {500, "internal_error"}
  @validation {422, "validation_failed"}

  @table %{
    401 => ~w[not_authenticated invalid_credentials invalid_token]a,
    403 => ~w[account_deactivated forbidden unauthorized not_zelador not_owner not_authorized]a,
    404 => ~w[not_found no_folder]a,
    409 => ~w[last_zelador not_pending invalid_status already_has_access already_readable
         already_bootstrapped not_bootstrapped circular_reference storage_quota_exceeded
         rkey_conflict chain_conflict expirada already_executed]a,
    422 => ~w[cannot_request_own cross_tekoa_owner cross_tekoa invalid_action mime_not_allowed
         missing_file invalid_tipo payload_invalido]a,
    429 => ~w[rate_limited]a,
    500 => ~w[envelope_invalido missing_mime missing_fecha_em bad_seq bad_link bad_entry
         bad_signature]a
  }

  @doc """
  O par {status, code} do motivo: o atomo mapeado leva o status da tabela e o
  proprio atomo como code; changeset e `validation_failed`; o resto, 500
  `internal_error`.
  """
  @spec resolve(term()) :: {non_neg_integer(), String.t()}
  def resolve(%Ecto.Changeset{}), do: @validation

  def resolve(reason) when is_atom(reason) do
    case status(reason) do
      nil -> @fallback
      status -> {status, Atom.to_string(reason)}
    end
  end

  def resolve(_reason), do: @fallback

  @doc "O status HTTP do motivo, ou nil quando o vocabulario nao o mapeia."
  @spec status(atom()) :: non_neg_integer() | nil
  def status(reason) do
    Enum.find_value(@table, fn {status, motivos} -> reason in motivos && status end)
  end
end
