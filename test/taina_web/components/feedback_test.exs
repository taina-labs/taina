defmodule TainaWeb.UI.FeedbackTest do
  @moduledoc """
  Testes de variante dos componentes de feedback (Wave 1b): empty_state
  (API nova body + :action, e o caminho legado hint/inner_block), error_card
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
    <.empty_state icon={@icon} title={@title} body={@body} hint={@hint} tag={@tag}>
      <:action :if={@with_action}>
        <.screen_button>Enviar arquivos</.screen_button>
      </:action>
      <div :if={@with_inner}>
        <.screen_button>botão da tela</.screen_button>
      </div>
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
        hint: nil,
        tag: "p",
        with_action: false,
        with_inner: false
      })

    render_component(&empty_state_component/1, assigns)
  end

  defp error_card_component(assigns) do
    ~H"""
    <.error_card title={@title} body={@body} retry_event={@retry_event} />
    """
  end

  defp error_card_html(opts) do
    assigns = Enum.into(opts, %{title: nil, body: nil, retry_event: nil})
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

  test "empty_state caminho legado hint: igual ao de antes" do
    html = empty_state_html(title: "Não deu para abrir a lixeira", hint: "Tente de novo.")

    assert html =~ "Não deu para abrir a lixeira"
    assert html =~ "Tente de novo."
  end

  test "empty_state tag do título (uso legado com hierarquia)" do
    html = empty_state_html(tag: "h2")

    assert html =~ "<h2 class=\"type-h3\">"
  end

  test "empty_state inner_block legado continua renderizando" do
    html = empty_state_html(with_inner: true)

    assert html =~ "botão da tela"
  end

  # ---------- ErrorCard ----------

  test "error_card: copy do board e Tentar de novo secundário repetindo o evento" do
    html = error_card_html(title: "Não conseguimos falar com a nuvem agora.", retry_event: "retry")

    assert html =~ "error-card"
    assert html =~ "error-card__head"
    assert html =~ "Não conseguimos falar com a nuvem agora."
    assert html =~ "Tentar de novo"
    assert html =~ "button--secondary"
    assert html =~ ~s(phx-click="retry")
    # ícone de alerta: nunca só cor
    assert html =~ ~s(y1="8" y2="12")
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

  # ---------- Skeleton ----------

  test "skeleton list_row: uma linha por count, cada uma com osso e texto" do
    html = skeleton_html(kind: "list_row", count: 3)

    assert html =~ "skeleton skeleton--list-row"
    assert html |> String.split("skeleton__row") |> length() == 4
    assert html =~ "skeleton__mark"
    assert html =~ "skeleton__line"
  end

  test "skeleton photo_grid: tiles da galeria" do
    html = skeleton_html(kind: "photo_grid", count: 8)

    assert html =~ "skeleton skeleton--photo-grid"
    assert length(Regex.scan(~r/skeleton__tile/, html)) == 8
  end

  test "skeleton card: títulos e linhas" do
    html = skeleton_html(kind: "card")

    assert html =~ "skeleton skeleton--card"
    assert html =~ "skeleton__card"
    assert html =~ "skeleton__line--title"
  end

  test "skeleton uso legado (class): bloco solto, igual de antes" do
    html = skeleton_html(class: "flex-1")

    assert html =~ ~s(class="skeleton flex-1")
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
