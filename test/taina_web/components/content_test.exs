defmodule TainaWeb.UI.ContentTest do
  @moduledoc """
  Testes de variante dos componentes de conteúdo (Wave 1a): badge (todos os
  kinds + variant legado), avatar (sm/md/lg + off) e service_square (cada
  mark + tone + caminho legado service/icon).
  """

  use ExUnit.Case, async: true
  use Phoenix.Component

  import Phoenix.LiveViewTest
  import TainaWeb.UI.Content

  # wrapper mínimo por componente (não sombreia o import)

  defp badge_component(assigns) do
    ~H"""
    <.badge kind={@kind} variant={@variant}>{@text}</.badge>
    """
  end

  defp avatar_component(assigns) do
    ~H"""
    <.avatar name={@name} size={@size} off={@off} inactive={@inactive} />
    """
  end

  defp service_square_component(assigns) do
    ~H"""
    <.service_square mark={@mark} service={@service} icon={@icon} tone={@tone} size={@size} />
    """
  end

  defp badge_html(opts) do
    assigns = Enum.into(opts, %{kind: nil, variant: nil, text: "Praça"})
    render_component(&badge_component/1, assigns)
  end

  defp avatar_html(opts \\ []) do
    assigns = Enum.into(opts, %{name: "Ana", size: "md", off: false, inactive: nil})
    render_component(&avatar_component/1, assigns)
  end

  defp square_html(opts \\ []) do
    assigns = Enum.into(opts, %{mark: nil, service: nil, icon: nil, tone: "neutral", size: "md"})
    render_component(&service_square_component/1, assigns)
  end

  # ---------- Badge ----------

  for kind <- ~w(praca casa zelador morador active inactive) do
    test "badge kind #{kind}" do
      html = badge_html(kind: unquote(kind))

      assert html =~ ~s(class="badge badge--#{unquote(kind)}")
      assert html =~ "Praça"
    end
  end

  test "badge variant deprecated: zelador passa direto" do
    html = badge_html(kind: nil, variant: "zelador")
    assert html =~ "badge--zelador"
  end

  test "badge variant deprecated: mods apagados mapeiam para kinds novos" do
    assert badge_html(kind: nil, variant: "ybira") =~ "badge--praca"
    assert badge_html(kind: nil, variant: "jaci") =~ "badge--casa"
    assert badge_html(kind: nil, variant: "soon") =~ "badge--inactive"
  end

  test "badge sem kind e sem variant levanta" do
    assert_raise ArgumentError, fn -> badge_html(kind: nil, variant: nil) end
  end

  # ---------- Avatar ----------

  test "avatar md (padrão): cor determinística pelo hash do nome" do
    html = avatar_html()

    assert html =~ "avatar"
    assert html =~ "A"
    assert html =~ ~r/avatar--[0-3]"/
  end

  test "avatar sm" do
    html = avatar_html(size: "sm")
    assert html =~ "avatar--sm"
  end

  test "avatar lg (novo tamanho)" do
    html = avatar_html(size: "lg")
    assert html =~ "avatar--lg"
  end

  test "avatar off: tinta neutra" do
    html = avatar_html(off: true)
    assert html =~ "avatar--off"
    assert html =~ "A"
  end

  test "avatar inactive deprecated mapeia para off" do
    html = avatar_html(inactive: true)
    assert html =~ "avatar--off"
  end

  # ---------- ServiceSquare ----------

  @mark_icons %{
    "ybira" => "M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9",
    "jaci" => "m21 15-3.086",
    "maraca" => "M20 13c0 5-3.5",
    "nhaman" => "M5.45 5.11",
    "doc" => "M15 2H6a2 2 0 0 0-2 2v16",
    "video" => "20 12 6 21 6 3",
    "neutral" => "M12 16v-4",
    "casa" => "M4,11.2L12,4L20,11.2",
    "praca" => "M4,19L20,19",
    "lixeira" => "M8.1,13L15.9,13",
    "mural" => "M15 12h-5",
    "saude" => "M2 9.5a5.5",
    "moradores" => "M3.6,19.5C3.6,16.2",
    "pedidos" => "M4,13L8.2,13",
    "privacidade" => "M8.5,10.5L8.5,8",
    "senha" => "M10.2,10.2L20,20",
    "dispositivos" => "M17.6,14.6L19.4,14.6",
    "sair" => "M13,4.5L5.5,4.5"
  }

  for mark <-
        ~w(ybira jaci maraca nhaman doc video neutral casa praca lixeira mural saude moradores pedidos privacidade senha dispositivos sair) do
    test "service_square mark #{mark}: tone neutral (padrão) e ícone derivado" do
      mark = unquote(mark)
      html = square_html(mark: mark)

      assert html =~ "service-square service-square--neutral service-square--#{mark}"
      assert html =~ Map.fetch!(@mark_icons, mark)
    end
  end

  test "service_square tone service" do
    html = square_html(mark: "ybira", tone: "service")

    assert html =~ "service-square--service"
    assert html =~ "service-square--ybira"
  end

  test "service_square size lg" do
    html = square_html(mark: "doc", size: "lg")
    assert html =~ "service-square--lg"
  end

  test "service_square caminho legado service + icon: marca mapeada e ícone do chamador" do
    html = square_html(service: "ybira", icon: "folder")

    assert html =~ "service-square--service service-square--ybira"
    # ícone legado passado (não o derivado do mark)
    assert html =~ "M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9"
  end

  test "service_square caminho legado service desconhecido cai no neutral" do
    html = square_html(service: "guara", icon: "user")
    assert html =~ "service-square service-square--neutral service-square--neutral"
  end

  test "service_square sem mark e sem par legado levanta" do
    assert_raise ArgumentError, fn -> square_html() end
  end
end
