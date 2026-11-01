defmodule TainaWeb.UI.OverlaysTest do
  @moduledoc """
  Testes de variante das sobreposições (Wave 1c): sheet actions/content,
  dialog confirm/destructive, menu (ícone sempre à esquerda, spec 10) e a
  composição actions_menu (um markup, Sheet no mobile e popover no desktop,
  spec 4.3).
  """

  use ExUnit.Case, async: true
  use Phoenix.Component

  import Phoenix.LiveViewTest
  import TainaWeb.UI.Overlays

  # wrappers mínimos (não usam os nomes dos componentes para não sombrear
  # o import)

  defp sheet_component(assigns) do
    ~H"""
    <.sheet id={@id} show={@show} on_cancel="close" title={@title} kind={@kind}>
      <:item :for={item <- @items} icon={item.icon} navigate={item[:navigate]} danger={item[:danger]}>
        {item.label}
      </:item>
    </.sheet>
    """
  end

  defp sheet_content_component(assigns) do
    ~H"""
    <.sheet id="sheet-casa" show={true} on_cancel="close" title="Sobre a casa" kind="content">
      Fica na sua casa. Só entra quem você deixar.
      <:action><button type="button">Entendi</button></:action>
    </.sheet>
    """
  end

  defp dialog_component(assigns) do
    ~H"""
    <.dialog
      id={@id}
      show={@show}
      kind={@kind}
      title={@title}
      body={@body}
      cancel_label={@cancel_label}
      confirm_label={@confirm_label}
      on_confirm="confirm"
      on_cancel="cancel"
    />
    """
  end

  defp modal_component(assigns) do
    ~H"""
    <.dialog id={@id} show={@show} on_cancel={ Phoenix.LiveView.JS.push("cancel") }>{@body}</.dialog>
    """
  end

  defp actions_menu_component(assigns) do
    ~H"""
    <.actions_menu id="actions-test" label={@label} title={@title}>
      <:item :for={item <- @items} icon={item.icon} navigate={item[:navigate]} kind={item[:kind]}>
        {item.label}
      </:item>
    </.actions_menu>
    """
  end

  defp menu_html(items) do
    assigns = %{items: items}
    render_component(&menu_component/1, assigns)
  end

  defp menu_component(assigns) do
    ~H"""
    <.menu id="menu-test" label="Mais opções">
      <:item :for={item <- @items} icon={item.icon} navigate={item[:navigate]} danger={item[:danger]}>
        {item.label}
      </:item>
    </.menu>
    """
  end

  @sheet_defaults %{id: "sheet-test", show: true, title: "Ações do arquivo", kind: "actions", items: []}

  defp sheet_html(opts \\ []) do
    assigns = Enum.into(opts, @sheet_defaults)
    render_component(&sheet_component/1, assigns)
  end

  defp sheet_content_html do
    render_component(&sheet_content_component/1, %{})
  end

  @dialog_defaults %{
    id: "dialog-test",
    show: true,
    kind: "confirm",
    title: "Publicar na praça?",
    body: "Todos os moradores vão poder ver e baixar este arquivo.",
    cancel_label: "Deixar na casa",
    confirm_label: "Publicar"
  }

  defp dialog_html(opts \\ []) do
    assigns = Enum.into(opts, @dialog_defaults)
    render_component(&dialog_component/1, assigns)
  end

  defp modal_html(opts \\ []) do
    assigns = Enum.into(opts, %{id: "modal-test", show: true, body: "Detalhes aqui"})
    render_component(&modal_component/1, assigns)
  end

  @menu_defaults %{id: "actions-test", label: "Mais opções", title: "Ações do arquivo", items: []}

  defp actions_menu_html(opts \\ []) do
    assigns = Enum.into(opts, @menu_defaults)
    render_component(&actions_menu_component/1, assigns)
  end

  # ---------- Sheet ----------

  test "sheet actions: painel, grabber, título e Fechar visível com ModalTrap" do
    html = sheet_html()

    assert html =~ ~s(class="sheet")
    assert html =~ "sheet__grabber"
    assert html =~ "Ações do arquivo"
    assert html =~ "Fechar"
    assert html =~ ~s(phx-hook="ModalTrap")
    assert html =~ ~s(role="dialog")
    assert html =~ ~s(aria-modal="true")
    # fechamento por esc antes do painel
    assert html =~ ~s(phx-key="escape")
  end

  test "sheet actions: itens no slot, ícone à esquerda e item danger" do
    items = [
      %{label: "Voltar para a casa", icon: "casa"},
      %{label: "Mover", icon: "folder"},
      %{label: "Remover", icon: "trash", danger: true}
    ]

    html = sheet_html(items: items)

    # dívida do Penpot resolvida no código: ícone sempre à esquerda
    assert html =~ ~r|<svg.*?</svg>\s*<span class="sheet__item-label">\s*Mover|ms
    assert html =~ "sheet__item--danger"
    assert html =~ ~r|<svg.*?</svg>\s*<span class="sheet__item-label">\s*Remover|ms
  end

  test "sheet fechado (show=false) não renderiza nada" do
    assert sheet_html(show: false) == ""
  end

  test "sheet content: corpo livre, ação única (Entendi) e Fechar" do
    html = sheet_content_html()

    assert html =~ "Sobre a casa"
    assert html =~ "Fica na sua casa. Só entra quem você deixar."
    assert html =~ "Entendi"
    assert html =~ "Fechar"
    assert html =~ "sheet__foot"
  end

  # ---------- Dialog ----------

  test "dialog confirm: botão seguro secundário e confirm primary; clique fora fecha" do
    html = dialog_html()

    assert html =~ ~s(class="dialog")
    assert html =~ "dialog__panel"
    assert html =~ "Publicar na praça?"
    assert html =~ "Deixar na casa"
    assert html =~ "button button--secondary"
    assert html =~ "button button--primary"
    refute html =~ "button--danger"
    assert html =~ ~s(phx-key="escape")
    assert html =~ ~s(phx-hook="ModalTrap")
    assert html =~ "phx-click-away"
  end

  test "dialog destructive: confirm vira danger e o clique fora NÃO fecha" do
    html =
      dialog_html(
        kind: "destructive",
        title: "Remover Estatuto.pdf?",
        body: "O arquivo vai para a lixeira e some de vez depois de 30 dias.",
        cancel_label: nil,
        confirm_label: "Remover"
      )

    assert html =~ "Remover Estatuto.pdf?"
    assert html =~ "O arquivo vai para a lixeira e some de vez depois de 30 dias."
    assert html =~ "button button--danger"
    assert html =~ "button button--secondary"
    assert html =~ "Cancelar"
    assert html =~ "Remover"
    refute html =~ "phx-click-away"
    assert html =~ ~s(phx-key="escape")
  end

  test "dialog destructive sem confirm_label cai no Remover do board" do
    html = dialog_html(kind: "destructive", confirm_label: nil)

    assert html =~ "Remover"
  end

  test "dialog fechado (show=false) não renderiza" do
    assert dialog_html(show: false) == ""
  end

  # ---------- dialog com corpo livre (slot :inner_block) ----------

  test "dialog com corpo livre: casca nova, SEM rodapé de confirmação" do
    html = modal_html()

    assert html =~ "dialog__panel"
    assert html =~ "Detalhes aqui"
    refute html =~ "dialog__actions"
  end

  test "dialog com corpo livre fecha com Esc e clique fora pelo on_cancel" do
    html = modal_html()

    assert html =~ ~s(phx-key="escape")
    assert html =~ "phx-click-away"
  end

  # ---------- Menu ----------

  test "menu: ícone sempre à esquerda do texto (spec 10)" do
    html = menu_html([%{label: "Abrir", icon: "file", navigate: "/documentos/ata"}])

    assert html =~ "menu__item"
    assert html =~ "href=\"/documentos/ata\""
    assert html =~ ~r|<svg.*?</svg>\s*Abrir|ms
  end

  test "menu: item danger mantém layout com o ícone à esquerda" do
    html = menu_html([%{label: "Remover", icon: "trash", danger: true}])

    assert html =~ "menu__item--danger"
    assert html =~ ~r|<svg.*?</svg>\s*Remover|ms
  end

  # ---------- ActionsMenu ----------

  test "actions_menu: gatilho kebab, painel com título e Fechar" do
    html = actions_menu_html()

    assert html =~ ~s(class="actions-menu")
    assert html =~ ~s(aria-label="Mais opções")
    assert html =~ ~s(aria-haspopup="menu")
    assert html =~ "actions-menu__panel"
    assert html =~ "Ações do arquivo"
    assert html =~ "actions-menu__close"
    assert html =~ "Fechar"
    refute html =~ ~s(phx-hook="ModalTrap")
  end

  test "actions_menu: itens com link e com kind danger" do
    items = [
      %{label: "Abrir", icon: "file", navigate: "/documentos/ata"},
      %{label: "Remover", icon: "trash", kind: "danger"}
    ]

    html = actions_menu_html(items: items)

    assert html =~ ~s(href="/documentos/ata")
    assert html =~ "actions-menu__item--danger"
    assert html =~ ~r|<svg.*?</svg>\s*<span class="actions-menu__item-label">\s*Remover|ms
  end
end
