defmodule TainaWeb.LayoutsTest do
  @moduledoc """
  Cascas novas do revamp (W2a, docs/web-revamp-spec.md, secao 5), puramente
  aditivo: flash + pular-para-conteudo primeiro, `main#main-content` sempre,
  uma casca por tela. `service` executa o `service_tab_bar` UMA vez (duas
  formas, barra no pe e fileira, trocam so pelo CSS, spec 4.3); `page`
  renderiza `page_header` e nenhuma aba; `hub` nao traz cabecalho; `viewer`
  e fullscreen e dispensa o skip-link; `auth` mostra o ConnectionNotice so
  fora de conexao segura e amarra o cartao em `--measure-card`. A decisao de
  conexao vive na funcao pura `secure_connection?/1` do Hooks.
  """

  use ExUnit.Case, async: true
  use Phoenix.Component

  import Phoenix.LiveViewTest
  import TainaWeb.Hooks, only: [secure_connection?: 1]

  alias TainaWeb.Layouts

  defp hub_html(opts \\ []) do
    assigns = Enum.into(opts, %{flash: %{}})

    rendered_to_string(~H"""
    <Layouts.hub flash={@flash}>
      <p>conteudo do hub</p>
    </Layouts.hub>
    """)
  end

  defp service_html(opts \\ []) do
    assigns =
      Enum.into(opts, %{
        flash: %{info: %{message: "salvo"}},
        service: "ybira",
        current: "praca",
        title: "Documentos",
        back: "/",
        back_label: nil,
        action: nil,
        fab: nil
      })

    rendered_to_string(~H"""
    <Layouts.service flash={@flash} service={@service} current={@current} title={@title} back={@back}>
      <:actions :if={@action}>{@action}</:actions>
      <:fab :if={@fab}>{@fab}</:fab>
      <p>conteudo</p>
    </Layouts.service>
    """)
  end

  defp page_html(opts \\ []) do
    assigns =
      Enum.into(opts, %{flash: %{}, title: "Mural", back: "/", back_label: nil, action: nil})

    rendered_to_string(~H"""
    <Layouts.page flash={@flash} title={@title} back={@back} back_label={@back_label}>
      <:action :if={@action}>{@action}</:action>
      <p>conteudo</p>
    </Layouts.page>
    """)
  end

  defp auth_html(opts \\ []) do
    assigns = Enum.into(Keyword.new(opts), %{flash: %{}})

    rendered_to_string(~H"""
    <Layouts.auth flash={@flash}>
      <p>conteudo</p>
    </Layouts.auth>
    """)
  end

  defp viewer_html do
    assigns = %{flash: %{}}

    rendered_to_string(~H"""
    <Layouts.viewer flash={@flash}>
      <p>conteudo</p>
    </Layouts.viewer>
    """)
  end

  defp count(html, payload), do: length(String.split(html, payload)) - 1

  describe "hub" do
    test "flash, skip-link e main#main-content na casca --hub" do
      html = hub_html()

      assert html =~ ~s(class="shell shell--hub")
      assert html =~ ~s(main class="shell shell--hub" id="main-content")
      assert html =~ ~s(class="skip-link")
      assert html =~ "Pular para o conteúdo"
      assert html =~ "conteudo do hub"
      # flash group entra sempre, mesmo sem mensagem
      assert html =~ "flash-group"
    end

    test "sem barra de cabecalho e sem abas" do
      html = hub_html()

      refute html =~ "page-header"
      refute html =~ "service-header"
      refute html =~ "service-tab-bar"
      refute html =~ "hub-header"
    end
  end

  describe "service" do
    test "service-header + service-tab-bar UMA vez (duas formas, o CSS troca em 768)" do
      html = service_html()

      assert html =~ ~s(class="shell shell--service")
      assert count(html, ~s(class="service-header")) == 1
      assert count(html, "service-tab-bar service-tab-bar--bar") == 1
      assert count(html, "service-tab-bar service-tab-bar--row") == 1
    end

    test "aba corrente leva aria-current, main#main-content e skip-link" do
      html = service_html()

      assert html =~ ~s(id="main-content")
      assert html =~ ~s(aria-current="page")
      assert html =~ "Documentos"
      assert html =~ "Pular para o conteúdo"
    end

    test "acoes e FAB opcionais: slots vazios somem, preenchidos aparecem" do
      vazio = service_html()
      refute vazio =~ "FAB-placeholder"

      cheio = service_html(action: "Enviar", fab: "FAB-acao")
      assert cheio =~ "Enviar"
      assert cheio =~ "FAB-acao"
    end

    test "jaci segue o mesmo casco" do
      html = service_html(service: "jaci", current: "timeline")

      assert count(html, ~s(class="service-header")) == 1
      assert count(html, "service-tab-bar service-tab-bar--bar") == 1
      assert html =~ "Linha do tempo"
    end
  end

  describe "page" do
    test "page_header e nenhuma aba" do
      html = page_html()

      assert html =~ ~s(class="shell shell--page")
      assert html =~ ~s(class="page-header")
      assert html =~ "Mural"
      refute html =~ "service-tab-bar"
      refute html =~ "service-header"
      assert html =~ ~s(id="main-content")
      assert html =~ "Pular para o conteúdo"
    end

    test "acao unica no cabecalho quando passada" do
      assert page_html(action: "acao-da-pagina") =~ "acao-da-pagina"
    end
  end

  describe "auth" do
    test "casca de auth: fundo solido e conteudo, sem cabecalho proprio" do
      html = auth_html()

      assert html =~ ~s(class="shell shell--auth")
      assert html =~ ~s(class="shell__content")
      assert html =~ "conteudo"
      refute html =~ "page-header"
      refute html =~ "service-tab-bar"
    end

    # O ConnectionNotice mora na tela, abaixo do cabecalho (board "sem https"),
    # nao na casca: a casca so da o fundo e o teto.
    test "a casca nao desenha o aviso de conexao" do
      refute auth_html() =~ "connection-notice"
    end

    test "sem cabecalho e sem abas sempre" do
      html = auth_html(secure: false)

      refute html =~ "page-header"
      refute html =~ "service-header"
      refute html =~ "service-tab-bar"
    end
  end

  describe "viewer" do
    test "fullscreen: sem skip-link, sem cabecalho, sem abas" do
      html = viewer_html()

      assert html =~ ~s(class="shell shell--viewer")
      refute html =~ "skip-link"
      refute html =~ "page-header"
      refute html =~ "service-header"
      refute html =~ "service-tab-bar"
      assert html =~ "conteudo"
      # avisos do visualizador atravessam a casca
      assert html =~ "flash-group"
    end
  end

  describe "TainaWeb.Hooks.secure_connection?/1" do
    test "https e seguro, haja o host que for" do
      assert secure_connection?("https://x")
      assert secure_connection?("https://taina.local:4000")
    end

    test "http em loopback e a propria maquina: seguro" do
      assert secure_connection?("http://localhost:4000")
      assert secure_connection?("http://127.0.0.1:4000")
      assert secure_connection?("http://[::1]:4000")
    end

    test "http fora do loopback (LAN ou mundo) e inseguro" do
      refute secure_connection?("http://taina.local:4000")
      refute secure_connection?("http://192.168.0.10:4000")
    end

    test "sem uri (valor ausente) assume segura, sem aviso sem prova" do
      assert secure_connection?(nil)
    end
  end
end
