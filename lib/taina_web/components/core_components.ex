defmodule TainaWeb.CoreComponents do
  @moduledoc """
  Cola da Phoenix e helpers de formatação para as telas: grupo de flash do
  LiveView, erros de changeset, aparência/kind de arquivo, bytes e tempo
  relativo. Os componentes visuais do design system vivem em
  `TainaWeb.Icons` e `TainaWeb.UI.*` (um módulo por família Penpot, ver
  docs/web-revamp-spec.md, 2.1), importados pelas telas via `html_helpers`.
  """

  use Phoenix.Component
  use Gettext, backend: TainaWeb.Gettext

  import TainaWeb.Icons

  alias Phoenix.LiveView.JS
  alias TainaWeb.Time

  @doc """
  Rótulo curto do tipo de arquivo para as linhas de lista ("PDF", "Imagem"...).
  """
  def file_kind("image/" <> _rest), do: gettext("Imagem")
  def file_kind("video/" <> _rest), do: gettext("Vídeo")
  def file_kind("audio/" <> _rest), do: gettext("Áudio")
  def file_kind("application/pdf"), do: "PDF"
  def file_kind("application/zip"), do: "ZIP"
  def file_kind("text/" <> _rest), do: gettext("Texto")
  def file_kind(_mime), do: gettext("Arquivo")

  @doc "Marca de serviço para um arquivo em uma linha de lista."
  def file_mark("image/" <> _rest), do: "jaci"
  def file_mark("video/" <> _rest), do: "video"
  def file_mark(_mime), do: "doc"

  # ---------- flash ----------

  attr :flash, :map, required: true

  def flash_group(assigns) do
    ~H"""
    <div class="flash-group">
      <.flash_message kind={:info} flash={@flash} />
      <.flash_message kind={:error} flash={@flash} />
    </div>
    """
  end

  attr :kind, :atom, required: true
  attr :flash, :map, required: true

  defp flash_message(assigns) do
    ~H"""
    <div
      :if={message = Phoenix.Flash.get(@flash, @kind)}
      id={"flash-#{@kind}"}
      class={"flash flash--#{@kind}"}
      data-kind={@kind}
      phx-hook={if @kind == :info, do: "FlashAutoDismiss"}
    >
      <.icon name={if @kind == :error, do: "alert", else: "info"} size={20} />
      <span
        class="flex-1"
        role={if @kind == :error, do: "alert", else: "status"}
        aria-live={if @kind == :error, do: "assertive", else: "polite"}
      >
        {message}
      </span>
      <button
        type="button"
        class="flash__dismiss"
        aria-label={gettext("Fechar aviso")}
        title={gettext("Fechar aviso")}
        phx-click={JS.push("lv:clear-flash", value: %{key: @kind})}
      >
        <.icon name="close" size={18} />
      </button>
    </div>
    """
  end

  # ---------- helpers de formatação ----------

  @doc """
  Bytes em texto humano, convenção pt-BR (vírgula decimal): `format_bytes(2_400_000)` retorna `"2,4 MB"`.
  """
  def format_bytes(nil), do: "0 B"
  def format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"

  def format_bytes(bytes) do
    {value, unit} =
      cond do
        bytes >= 1024 ** 4 -> {bytes / 1024 ** 4, "TB"}
        bytes >= 1024 ** 3 -> {bytes / 1024 ** 3, "GB"}
        bytes >= 1024 ** 2 -> {bytes / 1024 ** 2, "MB"}
        true -> {bytes / 1024, "KB"}
      end

    formatted =
      if value >= 10 do
        value |> round() |> Integer.to_string()
      else
        value |> Float.round(1) |> :erlang.float_to_binary(decimals: 1) |> String.replace(".", ",")
      end

    "#{formatted} #{unit}"
  end

  @doc "Lista nomes em pt-BR, com vírgulas e 'e' antes do último nome."
  def list_in_portuguese(names) when is_list(names) do
    case Enum.reverse(names) do
      [] -> ""
      [name] -> name
      [last | rest] -> Enum.join(Enum.reverse(rest), ", ") <> " #{gettext("e")} #{last}"
    end
  end

  @doc "Nome social para exibição, com o nome de usuário como reserva."
  def person_name(%{display_name: <<_::binary-size(1), _::binary>> = name}), do: name
  def person_name(%{username: name}) when is_binary(name), do: name
  def person_name(_ava), do: ""

  @doc """
  Tempo relativo curto em pt-BR: "hoje", "ontem", "há 3 dias", "há 2 semanas".
  """
  def relative_time(%DateTime{} = at), do: relative_time_days(Date.diff(Time.local_today(), Time.local_date(at)))
  def relative_time(%NaiveDateTime{} = at), do: relative_time_days(Date.diff(Time.local_today(), Time.local_date(at)))
  def relative_time(_other), do: ""

  defp relative_time_days(days) do
    cond do
      days <= 0 -> gettext("hoje")
      days == 1 -> gettext("ontem")
      days < 7 -> gettext("há %{count} dias", count: days)
      days < 14 -> gettext("há 1 semana")
      days < 30 -> gettext("há %{count} semanas", count: div(days, 7))
      days < 60 -> gettext("há 1 mês")
      true -> gettext("há %{count} meses", count: div(days, 30))
    end
  end

  @doc """
  Tradução de erros de changeset. As mensagens do Ecto chegam em inglês com
  interpolação `%{count}`; aqui interpolamos e deixamos a tradução para os
  arquivos `.po` (domínio "errors").
  """
  def translate_error({message, opts}) do
    if count = Keyword.get(opts, :count) do
      Gettext.dngettext(TainaWeb.Gettext, "errors", message, message, count, opts)
    else
      Gettext.dgettext(TainaWeb.Gettext, "errors", message, opts)
    end
  end
end
