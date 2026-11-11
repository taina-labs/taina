defmodule TainaWeb.UI.FeedbackTest do
  @moduledoc """
  Testes de variante dos componentes de feedback (Wave 1b): empty_state
  (API nova body + :action), error_card
  (retry), skeleton (kinds + count + uso legado) e connection_notice (copy
  verbatim do board).
  """

  use ExUnit.Case, async: true
  use Phoenix.Component

  import Phoenix.LiveViewTest
  import TainaWeb.UI.Feedback

  # wrapper mínimo por componente (não sombreia o import)

  defp empty_state_component(assigns) do
    ~H"""
    <.empty_state icon={@icon} title={@title} body={@body} tag={@tag}>
      <:action :if={@with_action}>
        <.screen_button>Enviar arquivos</.screen_button>
      </:action>
    </.empty_state>
    """
  end

  defp screen_button(assigns) do
    ~H"""
    <button class="button" type="button">{render_slot(@inner_block)}</button>
    """
  end

  defp empty_state_html(opts) do
    assigns =
      Enum.into(opts, %{
        icon: "folder",
        title: "Lixeira vazia",
        body: nil,
        tag: "p",
        with_action: false
      })

    render_component(&empty_state_component/1, assigns)
  end

  defp error_card_component(assigns) do
    ~H"""
    <.error_card
      title={@title}
      body={@body}
      retry_event={@retry_event}
      retry_label={@retry_label}
      retry_icon={@retry_icon}
      contact_event={@contact_event}
    />
    """
  end

  defp error_card_html(opts) do
    assigns =
      Enum.into(opts, %{
        title: nil,
        body: nil,
        retry_event: nil,
        retry_label: nil,
        retry_icon: "restore",
        contact_event: nil
      })

    render_component(&error_card_component/1, assigns)
  end

  defp skeleton_component(assigns) do
    ~H"""
    <.skeleton kind={@kind} count={@count} class={@class} />
    """
  end

  defp skeleton_html(opts) do
    assigns = Enum.into(opts, %{kind: nil, count: 1, class: ""})
    render_component(&skeleton_component/1, assigns)
  end

  defp connection_notice_component(assigns) do
    ~H"""
    <.connection_notice />
    """
  end

  defp connection_notice_html do
    render_component(&connection_notice_component/1, %{})
  end

  # ---------- EmptyState ----------

  test "empty_state API nova: icon, title e body" do
    html = empty_state_html(title: "Nada por aqui ainda", body: "Envie o primeiro arquivo da comunidade.")

    assert html =~ "empty-state"
    assert html =~ "Nada por aqui ainda"
    assert html =~ "Envie o primeiro arquivo da comunidade."
    # ícone default do corpo: folder
    assert html =~ "M20 20a2 2 0 0 0 2-2V8a2 2"
  end

  test "empty_state com :action" do
    html = empty_state_html(with_action: true)

    assert html =~ "Enviar arquivos"
    assert html =~ "button"
  end

  test "empty_state tag do título (uso legado com hierarquia)" do
    html = empty_state_html(tag: "h2")

    assert html =~ "<h2 class=\"type-h3\">"
  end

  # ---------- ErrorCard ----------

  test "error_card: copy do board e Tentar de novo secundário repetindo o evento" do
    html = error_card_html(title: "Não conseguimos falar com a nuvem agora.", retry_event: "retry")

    assert html =~ "error-card"
    assert html =~ "error-card__head"
    assert html =~ "Não conseguimos falar com a nuvem agora."
    assert html =~ "Tentar de novo"
    assert html =~ "button--secondary"
    assert html =~ ~S(phx-click="retry")
    # ícone de alerta (triângulo do Penpot): nunca só cor
    assert html =~ ~S(d="M12,2L22,22L2,22Z")
  end

  test "error_card sem body: só título e ação" do
    html = error_card_html(title: "Não conseguimos falar com a nuvem agora.", retry_event: "retry")

    refute html =~ "error-card__body"
  end

  test "error_card com body" do
    html = error_card_html(title: "Erro", body: "Pode ter sido um instante de rede.", retry_event: "retry-load")

    assert html =~ "error-card__body"
    assert html =~ "Pode ter sido um instante de rede."
  end

  test "error_card com contato: \"Falar com quem cuida\" discreto ao lado do retry" do
    html = error_card_html(title: "Este convite não é mais válido.", retry_event: "voltar", contact_event: "contato")

    assert html =~ "Falar com quem cuida"
    assert html =~ ~S(phx-click="contato")
    assert html =~ "button--ghost"
  end

  test "error_card sem contato: só o retry" do
    html = error_card_html(title: "Erro", retry_event: "retry")

    refute html =~ "Falar com quem cuida"
  end

  test "error_card aceita rótulo e ícone próprios (board de auth pede Voltar)" do
    html =
      error_card_html(
        title: "Este convite não é mais válido.",
        retry_event: "voltar",
        retry_label: "Voltar",
        retry_icon: "chevron-left"
      )

    assert html =~ "Voltar"
    assert html =~ ~S(d="m15 18-6-6 6-6")
    refute html =~ "Tentar de novo"
  end

  # ---------- Skeleton ----------

  test "skeleton list_row: uma linha por count, cada uma com osso e texto" do
    html = skeleton_html(kind: "list_row", count: 3)

    assert html =~ "skeleton skeleton--list-row"
    assert html |> String.split("skeleton__row") |> length() == 4
    assert html =~ "skeleton__mark"
    assert html =~ "skeleton__line"
  end

  test "skeleton photo_grid: unidades da grade da galeria" do
    html = skeleton_html(kind: "photo_grid", count: 8)

    assert html =~ "skeleton skeleton--photo-grid"
    assert Enum.count_until(Regex.scan(~r/skeleton__tile/, html), 9) == 8
  end

  test "skeleton card: títulos e linhas" do
    html = skeleton_html(kind: "card")

    assert html =~ "skeleton skeleton--card"
    assert html =~ "skeleton__card"
    assert html =~ "skeleton__line--title"
  end

  test "skeleton uso legado (class): bloco solto, igual de antes" do
    html = skeleton_html(class: "flex-1")

    assert html =~ ~S(class="skeleton flex-1")
    refute html =~ "skeleton--"
  end

  # ---------- ConnectionNotice ----------

  test "connection_notice: copy verbatim do board com ícone info" do
    html = connection_notice_html()

    assert html =~ "connection-notice"
    assert html =~ "connection-notice__icon"

    assert html =~
             "Esta conexão só fica protegida quando você está na rede da comunidade. Se não tiver certeza, fale com quem cuida antes de entrar."

    # info: circle + dica (nunca só cor)
    assert html =~ "M12 16v-4"
  end
end
