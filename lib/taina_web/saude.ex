defmodule TainaWeb.Saude do
  @moduledoc """
  A decisão de estado da Saúde, pura e única (docs/web-revamp-spec.md 6.1/6.4).

  O hub ("Da comunidade") e a página Saúde compartilham a mesma resposta para
  "está tudo em dia?": uma única linha, `:ok` ou `:attention`, extraída do
  estado do disco e do backup. Aqui é o lugar do veredito; as telas só ligam o
  resultado. Disco e backup são os mesmos fatos que `Ybira.storage_stats/1` e
  `Taina.Nhaman.Backup.last_backup/0` dão ao `SaudeLive`.

  Nenhuma consulta aqui: dados entram, frase sai. O limite compartilhado é o
  "acabando" do disco (90% da cota), o mesmo que o `SaudeLive` já usava.
  """

  use Gettext, backend: TainaWeb.Gettext

  # Limite "acabando" do disco: 90% da cota. Aviso ambiente, não alarme.
  @disk_warning_percent 90

  @type storage_stats :: %{used_bytes: integer(), quota_bytes: integer() | nil}
  @type summary :: %{state: :ok | :attention, line: String.t()}

  @doc "O último backup falhou? Só o `{:error, _}` chama atenção."
  @spec backup_attention?(term()) :: boolean()
  def backup_attention?({:error, _reason}), do: true
  def backup_attention?(_backup), do: false

  @doc """
  O disco está acabando? Cota inteira e maior que zero; sem cota (`nil`,
  disco inteiro) não há limite para estourar, então nunca chama atenção.
  """
  @spec disk_attention?(storage_stats()) :: boolean()
  def disk_attention?(%{used_bytes: used, quota_bytes: quota}) when is_integer(used) and is_integer(quota) and quota > 0,
    do: used / quota * 100 >= @disk_warning_percent

  def disk_attention?(_stats), do: false

  @doc """
  A linha de resumo da Saúde, copiada das telas Penpot:

    * em dia: "Backup em dia"
    * atenção (disco): "Disco quase cheio"
    * atenção (backup ilegível): "Último backup falhou"
    * atenção (nunca houve backup): "Nenhum backup ainda"

  O disco fala primeiro (é o fato mais apertado da caixa); o backup, depois.
  Aceita o mapa de blocos do hub: `%{storage: stats, backup: backup}`.
  """
  @spec summary_line(%{storage: storage_stats(), backup: term()}) :: summary()
  def summary_line(%{storage: storage, backup: backup}) do
    cond do
      disk_attention?(storage) -> %{state: :attention, line: gettext("Disco quase cheio")}
      backup_attention?(backup) -> %{state: :attention, line: backup_line(backup)}
      true -> %{state: :ok, line: gettext("Backup em dia")}
    end
  end

  # Caixa nova (reason :none/:no_dir) nunca teve backup: dizer que "falhou"
  # seria mentira (honestidade, RFC_003). Esse estado não está num board do
  # Penpot (os boards sempre mostram um backup existindo), então a frase é a
  # que o `SaudeLive` já dizia nesse caso.
  defp backup_line({:error, reason}) when reason in [:none, :no_dir], do: gettext("Nenhum backup ainda")
  defp backup_line(_backup), do: gettext("Último backup falhou")
end
