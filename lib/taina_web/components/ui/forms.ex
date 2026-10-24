defmodule TainaWeb.UI.Forms do
  @moduledoc """
  Campos de formulário do design system (Penpot, "01 - Componentes"), um
  `function component` por linha da tabela (docs/web-revamp-spec.md, 4.1):

  | Nome | Board id |
  | --- | --- |
  | Field | cc1037dc-e8ab-80cc-8008-d5d534bd4c68 |
  | Segmented | 3fd18cd2-90f8-80f3-8008-d59869333a5b |

  `radio_card` (RadioCard, 3fd18cd2-90f8-80f3-8008-d598201a40d0) e
  `connection_notice` (88db615f-12f9-80b9-8008-d62efd1e77ca) chegam na Wave 1.
  Importado pelas telas via `html_helpers`.
  """

  use Phoenix.Component
  use Gettext, backend: TainaWeb.Gettext

  import TainaWeb.CoreComponents
  import TainaWeb.Icons

  alias Phoenix.HTML.FormField

  # ---------- campos ----------

  @doc """
  Campo de formulário com rótulo, ajuda e erros. Aceita `Phoenix.HTML.FormField`.

      <.input field={@form[:username]} type="text" label="Nome de usuário" />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any
  attr :type, :string, default: "text"
  attr :help, :string, default: nil
  attr :icon, :string, default: nil
  attr :field, FormField, doc: "ex.: @form[:username]"
  attr :errors, :list, default: []

  slot :trailing,
    doc: "controle anexo à direita do campo (ex.: <.password_toggle>); quando presente, substitui o ícone decorativo"

  attr :rest, :global, include: ~w(autocomplete placeholder required minlength maxlength inputmode autofocus)

  def input(%{field: %FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error/1))
    |> assign_new(:name, fn -> field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  # Sem `field`, os attrs `name`/`value` não têm default (o default apagaria o
  # valor vindo de `assign_new` na cláusula de `FormField`), então entram aqui
  # como nil: um `@value` ausente derrubaria a renderização com KeyError.
  def input(assigns) do
    assigns =
      assigns
      |> assign_new(:name, fn -> nil end)
      |> assign_new(:value, fn -> nil end)

    ~H"""
    <div class={["field", @errors != [] && "field--invalid"]}>
      <label :if={@label} for={@id}>{@label}</label>
      <div class="field__control">
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          aria-invalid={@errors != [] && "true" || nil}
          aria-describedby={input_describedby(@id, @help, @errors)}
          {@rest}
        />
        {render_slot(@trailing)}
        <.icon :if={@icon && @trailing == []} name={@icon} size={20} />
      </div>
      <span :if={@help && @errors == []} class="field__help" id={"#{@id}-help"}>{@help}</span>
      <span
        :for={{error, index} <- Enum.with_index(@errors)}
        class="field__error"
        id={"#{@id}-error-#{index}"}
        role="alert"
      >{error}</span>
    </div>
    """
  end

  # O span de ajuda só entra quando não há erro (mesma condição do template).
  defp input_describedby(nil, _help, _errors), do: nil

  defp input_describedby(id, help, errors) do
    help_ids = if help && errors == [], do: ["#{id}-help"], else: []
    error_ids = Enum.with_index(errors, fn _error, index -> "#{id}-error-#{index}" end)

    case help_ids ++ error_ids do
      [] -> nil
      ids -> Enum.join(ids, " ")
    end
  end

  @doc """
  Alternância mostrar/ocultar senha para o campo de senha de id `target`
  (dentro do slot `:trailing` do `input/1`). O estado fica no botão
  (`aria-pressed`) e o hook `PasswordToggle` troca o `type` do input; os
  rótulos viajam nos data-attrs, então o gettext continua no servidor.

      <.input type="password" id="login_password" ...>
        <:trailing><.password_toggle target="login_password" /></:trailing>
      </.input>
  """
  attr :target, :string, required: true, doc: "id do input de senha alvo"

  def password_toggle(assigns) do
    # O `phx-hook` exige `id`: deriva do alvo, único por campo.
    assigns = assign(assigns, :id, "#{assigns.target}-toggle")

    ~H"""
    <button
      type="button"
      id={@id}
      class="icon-btn"
      phx-hook="PasswordToggle"
      data-target={@target}
      data-label-show={gettext("Mostrar senha")}
      data-label-hide={gettext("Ocultar senha")}
      aria-pressed="false"
      aria-label={gettext("Mostrar senha")}
    >
      <.icon name="eye" size={20} />
    </button>
    """
  end

  @doc """
  Campo de seleção com o mesmo esquema de rótulo/ajuda/erro do `input/1`.

      <.select field={@form[:plano]} label="Plano" options={[@plano, ...]} prompt="Selecione..." />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any
  attr :help, :string, default: nil
  attr :field, FormField, doc: "ex.: @form[:plano]"
  attr :errors, :list, default: []
  attr :prompt, :string, default: nil, doc: ~s{opção vazia (value=""), ex.: "Selecione..."}
  attr :options, :list, required: true, doc: "pares {valor, rótulo}"
  attr :rest, :global, include: ~w(required autofocus)

  def select(%{field: %FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error/1))
    |> assign_new(:name, fn -> field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> select()
  end

  def select(assigns) do
    assigns =
      assigns
      |> assign_new(:name, fn -> nil end)
      |> assign_new(:value, fn -> nil end)

    ~H"""
    <div class={["field", @errors != [] && "field--invalid"]}>
      <label :if={@label} for={@id}>{@label}</label>
      <div class="field__control">
        <select
          name={@name}
          id={@id}
          aria-invalid={@errors != [] && "true" || nil}
          aria-describedby={input_describedby(@id, @help, @errors)}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          <option :for={{value, label} <- @options} value={value} selected={value == @value}>{label}</option>
        </select>
      </div>
      <span :if={@help && @errors == []} class="field__help" id={"#{@id}-help"}>{@help}</span>
      <span
        :for={{error, index} <- Enum.with_index(@errors)}
        class="field__error"
        id={"#{@id}-error-#{index}"}
        role="alert"
      >{error}</span>
    </div>
    """
  end

  @doc """
  Área de texto multi-linha com o mesmo esquema de rótulo/ajuda/erro do `input/1`.

      <.textarea field={@form[:resumo]} label="Resumo" rows={4} />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any
  attr :help, :string, default: nil
  attr :field, FormField, doc: "ex.: @form[:resumo]"
  attr :errors, :list, default: []
  attr :rest, :global, include: ~w(placeholder required rows maxlength minlength inputmode autofocus)

  def textarea(%{field: %FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error/1))
    |> assign_new(:name, fn -> field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> textarea()
  end

  def textarea(assigns) do
    assigns =
      assigns
      |> assign_new(:name, fn -> nil end)
      |> assign_new(:value, fn -> nil end)

    ~H"""
    <div class={["field", @errors != [] && "field--invalid"]}>
      <label :if={@label} for={@id}>{@label}</label>
      <div class="field__control">
        <textarea
          name={@name}
          id={@id}
          aria-invalid={@errors != [] && "true" || nil}
          aria-describedby={input_describedby(@id, @help, @errors)}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </div>
      <span :if={@help && @errors == []} class="field__help" id={"#{@id}-help"}>{@help}</span>
      <span
        :for={{error, index} <- Enum.with_index(@errors)}
        class="field__error"
        id={"#{@id}-error-#{index}"}
        role="alert"
      >{error}</span>
    </div>
    """
  end

  # ---------- controle segmentado ----------

  @doc """
  Alternador de visões (Grade / Linha do tempo).

      <.segmented>
        <:option patch={~p"/fotos"} current={@live_action == :grid}>Grade</:option>
        <:option patch={~p"/fotos/linha-do-tempo"} current={@live_action == :timeline}>Linha do tempo</:option>
      </.segmented>
  """
  slot :option, required: true do
    attr :patch, :string, required: true
    attr :current, :boolean
  end

  def segmented(assigns) do
    ~H"""
    <div class="segmented" role="group" aria-label={gettext("Ver como")}>
      <.link
        :for={option <- @option}
        patch={option.patch}
        class="segmented__option"
        aria-current={option[:current] && "page" || nil}
      >
        {render_slot(option)}
      </.link>
    </div>
    """
  end
end
