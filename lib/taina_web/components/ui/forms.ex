defmodule TainaWeb.UI.Forms do
  @moduledoc """
  Campos de formulário do design system (Penpot, "01 - Componentes"), um
  `function component` por linha da tabela (docs/web-revamp-spec.md, 4.1):

  | Nome | Board id |
  | --- | --- |
  | Field | cc1037dc-e8ab-80cc-8008-d5d534bd4c68 |
  | Segmented | 3fd18cd2-90f8-80f3-8008-d59869333a5b |
  | RadioCard | 3fd18cd2-90f8-80f3-8008-d598201a40d0 |

  `connection_notice` (88db615f-12f9-80b9-8008-d62efd1e77ca) chega na Wave 1.
  Importado pelas telas via `html_helpers`.
  """

  use Phoenix.Component
  use Gettext, backend: TainaWeb.Gettext

  import TainaWeb.CoreComponents
  import TainaWeb.Icons

  alias Phoenix.HTML.FormField

  # ---------- campos ----------

  @doc """
  Campo de formulário (Penpot Field: Kind text/password/search/address, State
  invalid/filled/disabled) com rótulo, ajuda e erros. Aceita
  `Phoenix.HTML.FormField`.

      <.field field={@form[:username]} label="Nome de usuário" />
      <.field field={@form[:senha]} kind="password" />
  """
  attr :kind, :string, default: "text", values: ~w(text password search address)

  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any
  attr :help, :string, default: nil
  attr :field, FormField, doc: "ex.: @form[:username]"
  attr :errors, :list, default: []

  slot :trailing,
    doc: "controle anexo à direita do campo (ex.: <.password_toggle>)"

  attr :rest, :global, include: ~w(autocomplete placeholder required minlength maxlength inputmode autofocus)

  def field(%{field: %FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error/1))
    |> assign_new(:name, fn -> field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> resolve_field()
    |> field()
  end

  # Sem `field`, os attrs `name`/`value` não têm default (o default apagaria o
  # valor vindo de `assign_new` na cláusula de `FormField`), então entram aqui
  # como nil: um `@value` ausente derrubaria a renderização com KeyError.
  def field(assigns) do
    assigns =
      assigns
      |> assign_new(:name, fn -> nil end)
      |> assign_new(:value, fn -> nil end)
      |> resolve_field()

    ~H"""
    <div class={["field", @kind in ~w(password search address) && "field--#{@kind}", @errors != [] && "field--invalid"]}>
      <label :if={@label} for={@id}>{@label}</label>
      <div class={["field__control", @kind == "search" && "search"]}>
        <.icon :if={@kind == "search"} name="search" size={20} class="field__icon" />
        <.icon :if={@kind == "address"} name="servidor" size={20} class="field__icon field__icon--leading" />
        <input
          type={@input_type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@input_type, @value)}
          aria-invalid={@errors != [] && "true" || nil}
          aria-describedby={describedby(@id, @help, @errors)}
          {@rest}
        />
        {render_slot(@trailing)}
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

  defp resolve_field(assigns) do
    input_type =
      case assigns[:kind] do
        "password" -> "password"
        "search" -> "search"
        "address" -> "text"
        _ -> "text"
      end

    assign(assigns, :input_type, input_type)
  end

  # O span de ajuda só entra quando não há erro (mesma condição do template).
  defp describedby(nil, _help, _errors), do: nil

  defp describedby(id, help, errors) do
    help_ids = if help && errors == [], do: ["#{id}-help"], else: []
    error_ids = Enum.with_index(errors, fn _error, index -> "#{id}-error-#{index}" end)

    case help_ids ++ error_ids do
      [] -> nil
      ids -> Enum.join(ids, " ")
    end
  end

  @doc """
  Alternância mostrar/ocultar senha para o campo de senha de id `target`
  (dentro do slot `:trailing` do `field/1`). Board (`Auth / Entrar`): o
  controle é a palavra "Mostrar", dentro da caixa, encostada à direita - não
  é um ícone nem um botão do lado de fora. O estado fica no botão
  (`aria-pressed`) e o hook `PasswordToggle` troca o `type` do input e a
  palavra visível; os textos viajam nos data-attrs, então o gettext continua
  no servidor.

      <.field field={@form[:password]} kind="password" id="login_password" ...>
        <:trailing><.password_toggle target="login_password" /></:trailing>
      </.field>
  """
  attr :target, :string, required: true, doc: "id do input de senha alvo"

  def password_toggle(assigns) do
    # O `phx-hook` exige `id`: deriva do alvo, único por campo.
    assigns = assign(assigns, :id, "#{assigns.target}-toggle")

    ~H"""
    <button
      type="button"
      id={@id}
      class="field__toggle"
      phx-hook="PasswordToggle"
      data-target={@target}
      data-label-show={gettext("Mostrar senha")}
      data-label-hide={gettext("Ocultar senha")}
      data-text-show={gettext("Mostrar")}
      data-text-hide={gettext("Ocultar")}
      aria-pressed="false"
      aria-label={gettext("Mostrar senha")}
    >
      <span class="field__toggle-label">{gettext("Mostrar")}</span>
    </button>
    """
  end

  # ---------- cartão de rádio ----------

  @doc """
  Cartão de rádio (Penpot: RadioCard, State default/selected): label com um
  input de rádio nativo escondido, descrição e anel indicador.

      <.radio_card field={@form[:escolha]} value="inteiro" label="O disco inteiro" />

  O `field` aceita `Phoenix.HTML.FormField` ou um `name` plano; o estado vem
  do rádio (igual ao HTML), o card só reflete `checked`.
  """
  attr :field, :any, doc: "ex.: @form[:escolha], ou o name plano (\"escolha\")"
  attr :value, :string, required: true
  attr :label, :string, required: true
  attr :description, :string, default: nil
  attr :rest, :global, include: ~w(autofocus)

  def radio_card(%{field: %FormField{} = field} = assigns) do
    assigns
    |> assign(
      field: nil,
      name: field.name,
      id: "#{field.id}-#{assigns.value}",
      checked: Phoenix.Component.used_input?(field) && value_checked?(field.value, assigns.value)
    )
    |> do_radio_card()
  end

  def radio_card(%{field: name} = assigns) when is_binary(name) do
    assigns
    |> assign(field: nil, name: name, id: nil, checked: false)
    |> do_radio_card()
  end

  def radio_card(assigns) do
    assigns
    |> assign_new(:name, fn -> nil end)
    |> assign_new(:id, fn -> nil end)
    |> assign_new(:checked, fn -> false end)
    |> do_radio_card()
  end

  defp do_radio_card(assigns) do
    ~H"""
    <label class={["radio-card", @checked && "radio-card--selected"]}>
      <input type="radio" class="radio-card__input" name={@name} id={@id} value={@value} checked={@checked} {@rest} />
      <span class="radio-card__body">
        <span class="radio-card__label">{@label}</span>
        <span :if={@description} class="radio-card__description">{@description}</span>
      </span>
      <span class="radio-card__ring" aria-hidden="true"></span>
    </label>
    """
  end

  defp value_checked?(field_value, value), do: to_string(field_value) == value
end
