defmodule TainaWeb.UI.ActionsTest do
  @moduledoc """
  Testes de variante dos componentes de ação (Wave 1a): um por valor de
  variante, conferindo o modifier BEM.

  Nota: para componentes de função, `Phoenix.LiveViewTest.render_component/2`
  já devolve o HTML como string; o `rendered_to_string/1` é para `%Rendered{}`
  de telas e escaparia o resultado.
  """

  use ExUnit.Case, async: true
  use Phoenix.Component

  import Phoenix.LiveViewTest
  import TainaWeb.UI.Actions

  # Slots não atravessam `render_component` diretamente: o "call site" aqui é
  # um wrapper mínimo por componente (os wrappers NÃO usam os nomes dos
  # componentes para não sombrear o import dentro do wrapper).

  defp button_component(assigns) do
    ~H"""
    <.button kind={@kind} size={@size} icon={@icon} loading={@loading} navigate={@navigate} class={@class}>
      Salvar
    </.button>
    """
  end

  defp icon_button_component(assigns) do
    ~H"""
    <.icon_button name={@name} label={@label} kind={@kind} navigate={@navigate} />
    """
  end

  defp fab_component(assigns) do
    ~H"""
    <.fab label={@label} icon={@icon} navigate={@navigate} uploading={@uploading} />
    """
  end

  defp html_button(opts \\ []) do
    assigns = Enum.into(opts, %{kind: nil, size: "lg", icon: "none", loading: false, navigate: nil, class: nil})

    render_component(&button_component/1, assigns)
  end

  defp html_icon_button(opts \\ []) do
    assigns = Enum.into(opts, %{name: "kebab", label: "Mais opções", kind: nil, navigate: nil})
    render_component(&icon_button_component/1, assigns)
  end

  defp fab_html(opts \\ []) do
    assigns = Enum.into(opts, %{label: "Enviar", icon: "plus", navigate: nil, uploading: false})
    render_component(&fab_component/1, assigns)
  end

  # ---------- Button ----------

  for kind <- ~W(primary secondary ghost danger) do
    test "button kind #{kind}" do
      html = html_button(kind: unquote(kind))

      assert html =~ "button button--#{unquote(kind)} button--lg"
      assert html =~ "Salvar"
    end
  end

  for size <- ~W(sm md lg) do
    test "button size #{size}" do
      html = html_button(size: unquote(size))

      assert html =~ "button--#{unquote(size)}"
    end
  end

  test "button sem kind cai no primary" do
    assert html_button() =~ "button--primary"
  end

  test "button loading: aria-busy, disabled e modifier" do
    html = html_button(loading: true)

    assert html =~ "button--loading"
    assert html =~ "disabled"
    assert html =~ "aria-busy"
  end

  test "button ícone leading chega como <.icon> do design system" do
    html = html_button(icon: "plus")

    assert html =~ ~S(class="icon )
    assert html =~ "M5 12h14"
  end

  test "button icon none não rende ícone" do
    html = html_button(icon: nil)

    refute html =~ "M5 12h14"
  end

  test "button navigate vira link" do
    html = html_button(navigate: "/convite")

    assert html =~ ~S(href="/convite")
  end

  # ---------- IconButton ----------

  test "icon_button kind default" do
    html = html_icon_button(kind: "default")

    assert html =~ "icon-button icon-button--default"
  end

  test "icon_button kind danger" do
    html = html_icon_button(kind: "danger")

    assert html =~ "icon-button--danger"
  end

  test "icon_button guarda o rótulo no aria-label e no title" do
    html = html_icon_button()

    assert html =~ ~S(aria-label="Mais opções")
    assert html =~ ~S(title="Mais opções")
  end

  test "icon_button sem navigate vira <button>" do
    assert html_icon_button() =~ "<button"
  end

  test "icon_button navigate vira <a>" do
    html = html_icon_button(navigate: "/conta")

    assert html =~ "<a"
    assert html =~ ~S(href="/conta")
  end

  # ---------- FAB ----------

  test "fab renderiza pílula estendida com rótulo sempre visível" do
    html = fab_html()

    assert html =~ "fab"
    assert html =~ "fab__label"
    refute html =~ "aria-label"
    assert html =~ "Enviar"
  end

  test "fab uploading: modifier + aria-busy" do
    html = fab_html(uploading: true)

    assert html =~ "fab--uploading"
    assert html =~ "aria-busy"
  end

  test "fab navigate vira link" do
    html = fab_html(navigate: "/documentos/enviar")

    assert html =~ ~S(href="/documentos/enviar")
  end

  test "fab sem navigate vira <button> com o ícone do design system" do
    html = fab_html()

    assert html =~ "<button"
    assert html =~ "M5 12h14"
  end
end
