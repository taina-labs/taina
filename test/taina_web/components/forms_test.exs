defmodule TainaWeb.UI.FormsTest do
  @moduledoc """
  Testes de variante dos componentes de formulário (Wave 1a): field (kinds
  text/password/search/address + aria/erros), segmented (selected) e
  radio_card (selected). Confere o BEM novo e os comportamentos de
  acessibilidade (aria-invalid, role alert, aria-current).
  """

  use ExUnit.Case, async: true
  use Phoenix.Component

  import Phoenix.LiveViewTest
  import TainaWeb.UI.Forms

  # wrapper mínimo por componente (não sombreia o import)

  defp field_component(assigns) do
    ~H"""
    <.field kind={@kind} type={@type} id={@id} name={@name} label={@label} value={@value} help={@help} errors={@errors} icon={@icon} />
    """
  end

  defp segmented_component(assigns) do
    ~H"""
    <.segmented>
      <:option patch="/galeria" selected={@grade_selected} current={@grade_current}>Grade</:option>
      <:option patch="/galeria/linha-do-tempo">Linha do tempo</:option>
    </.segmented>
    """
  end

  defp radio_card_component(assigns) do
    ~H"""
    <.radio_card field={@field} value={@value} label={@label} description={@description} />
    """
  end

  defp field_html(opts \\ []) do
    assigns = Enum.into(opts, field_assigns())
    render_component(&field_component/1, assigns)
  end

  defp field_assigns do
    %{
      kind: "text",
      type: nil,
      id: "campo",
      name: "campo",
      label: "Nome",
      value: nil,
      help: nil,
      errors: [],
      icon: nil,
      field: nil
    }
  end

  defp segmented_html(opts \\ []) do
    assigns = Enum.into(opts, %{grade_selected: false, grade_current: false})
    render_component(&segmented_component/1, assigns)
  end

  defp radio_card_html(opts) do
    assigns =
      Enum.into(opts, %{field: nil, value: "inteiro", label: "O disco inteiro", description: nil})

    render_component(&radio_card_component/1, assigns)
  end

  defp form_field(name, value) do
    %{name => value}
    |> Phoenix.Component.to_form(as: "escolha")
    |> Access.fetch!(name)
  end

  # ---------- Field: kinds ----------

  test "field kind text (padrão): sem modifier de kind, input text" do
    html = field_html()

    assert html =~ ~s(<div class="field)
    refute html =~ "field--"
    assert html =~ ~s(type="text")
    assert html =~ "<label"
  end

  test "field kind password" do
    html = field_html(kind: "password", value: "segredo")

    assert html =~ "field--password"
    assert html =~ ~s(type="password")
  end

  test "field kind search usa o bloco .search órfão e icon de busca" do
    html = field_html(kind: "search")

    assert html =~ "field--search"
    assert html =~ ~s(class="field__control search")
    assert html =~ ~s(type="search")
  end

  test "field kind address: ícone servidor à esquerda (paridade Penpot)" do
    html = field_html(kind: "address")

    assert html =~ "field--address"
    assert html =~ "field__icon--leading"
    # markup do ícone `servidor`
    assert html =~ "M7,6.7L7.01,6.7"
    assert html =~ ~s(type="text")
  end

  test "field type deprecated mantém o input HTML (number)" do
    html = field_html(type: "number", value: 10)

    assert html =~ ~s(type="number")
  end

  # ---------- Field: acessibilidade e erros ----------

  test "field com erro: aria-invalid, role alert" do
    html = field_html(errors: ["obrigatório"])

    assert html =~ "field--invalid"
    assert html =~ ~s(aria-invalid="true")
    assert html =~ ~s(role="alert")
    assert html =~ "obrigatório"
  end

  test "field sem erro: não marca aria-invalid" do
    html = field_html()
    refute html =~ "aria-invalid"
  end

  test "field ajuda vira aria-describedby" do
    html = field_html(help: "sem espaços")

    assert html =~ ~s(id="campo-help")
    assert html =~ ~s(aria-describedby="campo-help")
  end

  # ---------- Segmented ----------

  test "segmented selecionada: modifier + aria-current (superfície elevada no CSS)" do
    html = segmented_html(grade_selected: true)

    assert html =~ ~s(class="segmented__option segmented__option--selected")
    assert html =~ ~s(aria-current="page")
    # a não selecionada não marca modifier nem aria-current
    assert html =~ ~s(class="segmented__option")
    assert html =~ "Linha do tempo"
  end

  test "segmented option attr current deprecated mapeia para selected" do
    html = segmented_html(grade_current: true)

    assert html =~ "segmented__option--selected"
    assert html =~ ~s(aria-current="page")
  end

  test "segmented sem seleção não marca aria-current" do
    html = segmented_html()

    refute html =~ "aria-current"
    refute html =~ "segmented__option--selected"
  end

  # ---------- RadioCard ----------

  test "radio_card com FormField no valor selecionado: modifier + checked" do
    html = radio_card_html(field: form_field("escolha", "inteiro"), value: "inteiro")

    assert html =~ "radio-card radio-card--selected"
    assert html =~ ~s(type="radio")
    assert html =~ "checked"
    assert html =~ "O disco inteiro"
  end

  test "radio_card FormField com valor diferente: sem modifier" do
    html = radio_card_html(field: form_field("escolha", "limite"), value: "inteiro")

    assert html =~ "radio-card"
    refute html =~ "radio-card--selected"
  end

  test "radio_card sem FormField (name plano): default sem selected" do
    html = radio_card_html(field: "escolha")

    refute html =~ "radio-card--selected"
    assert html =~ ~s(name="escolha")
  end

  test "radio_card descrição e anel visuais" do
    html = radio_card_html(field: "escolha", description: "sem limite")

    assert html =~ "radio-card__ring"
    assert html =~ "radio-card__description"
    assert html =~ "sem limite"
  end
end
