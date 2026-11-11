defmodule TainaWeb.Icons do
  @moduledoc """
  Ícones do design system (página "01 - Componentes" do Penpot) como SVG
  inline, sem icon font, sem requisição extra. Os paths são o conjunto
  outline do Lucide (ISC), 24x24, stroke 2, pontas arredondadas.

  O componente `icon/1` vive neste módulo e é importado pelas telas via
  `html_helpers`; os paths ficam no mapa `@paths` abaixo.

  O `size` continua numérico (docs/web-revamp-spec.md, 4.2); a escala padrão
  espelha os tokens `--size-icon-md` (24) e `--size-icon-lg` (28).
  """

  use Phoenix.Component

  @paths %{
    "folder" =>
      ~S(<path d="M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"/>),
    "folder-plus" =>
      ~S(<path d="M12 10v6"/><path d="M9 13h6"/><path d="M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"/>),
    "image" =>
      ~S(<rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/>),
    "search" => ~S(<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>),
    "plus" => ~S(<path d="M5 12h14"/><path d="M12 5v14"/>),
    "upload" =>
      ~S(<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" x2="12" y1="3" y2="15"/>),
    "download" =>
      ~S(<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" x2="12" y1="15" y2="3"/>),
    "share" =>
      ~S(<path d="M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8"/><polyline points="16 6 12 2 8 6"/><line x1="12" x2="12" y1="2" y2="15"/>),
    "chevron-left" => ~S(<path d="m15 18-6-6 6-6"/>),
    "chevron-right" => ~S(<path d="m9 18 6-6-6-6"/>),
    "kebab" => ~S(<circle cx="12" cy="12" r="1"/><circle cx="12" cy="5" r="1"/><circle cx="12" cy="19" r="1"/>),
    "dots" => ~S(<circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/><circle cx="5" cy="12" r="1"/>),
    "trash" =>
      ~S(<path d="M3 6h18"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"/><path d="M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/>),
    "grid" =>
      ~S(<rect width="7" height="7" x="3" y="3" rx="1"/><rect width="7" height="7" x="14" y="3" rx="1"/><rect width="7" height="7" x="14" y="14" rx="1"/><rect width="7" height="7" x="3" y="14" rx="1"/>),
    "check" => ~S(<path d="M20 6 9 17l-5-5"/>),
    "close" => ~S(<path d="M18 6 6 18"/><path d="m6 6 12 12"/>),
    "clock" => ~S(<circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>),
    "link" =>
      ~S(<path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>),
    "shield" =>
      ~S(<path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z"/>),
    "user" => ~S(<path d="M20 21a8 8 0 0 0-16 0"/><circle cx="12" cy="8" r="4"/>),
    "mural" =>
      ~S(<path d="M15 12h-5"/><path d="M15 8h-5"/><path d="M19 17V5a2 2 0 0 0-2-2H4"/><path d="M8 21h12a2 2 0 0 0 2-2v-1a1 1 0 0 0-1-1H11a1 1 0 0 0-1 1v1a2 2 0 1 1-4 0V5a2 2 0 1 0-4 0v2a1 1 0 0 0 1 1h3"/>),
    "saude" =>
      ~S(<path d="M2 9.5a5.5 5.5 0 0 1 9.591-3.676.56.56 0 0 0 .818 0A5.49 5.49 0 0 1 22 9.5c0 2.29-1.5 4-3 5.5l-5.492 5.313a2 2 0 0 1-3 .019L5 15c-1.5-1.5-3-3.2-3-5.5"/><path d="M3.22 13H9.5l.5-1 2 4.5 2-7 1.5 3.5h5.27"/>),
    "file" =>
      ~S(<path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/>),
    "restore" => ~S(<path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/><path d="M3 3v5h5"/>),
    "play" => ~S(<polygon points="6 3 20 12 6 21 6 3"/>),
    "pencil" => ~S(<path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z"/><path d="m15 5 4 4"/>),
    "move" => ~S(<polyline points="15 14 20 9 15 4"/><path d="M4 20v-7a4 4 0 0 1 4-4h12"/>),
    "disk" =>
      ~S(<line x1="22" x2="2" y1="12" y2="12"/><path d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"/><line x1="6" x2="6.01" y1="16" y2="16"/><line x1="10" x2="10.01" y1="16" y2="16"/>),
    "info" => ~S(<circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/>),
    "alert" =>
      ~S(<circle cx="12" cy="12" r="10"/><line x1="12" x2="12" y1="8" y2="12"/><line x1="12" x2="12.01" y1="16" y2="16"/>),
    # triângulo do Penpot (`ic / warning`), 20x20 centrado no viewBox 24
    "warning" => ~S(<path d="M12,2L22,22L2,22Z"/>),
    # Penpot-only icons (docs/web-revamp-spec.md, 4.2): extraídos da board
    # "Icon / *" e reduzidos ao markup interno.
    "casa" =>
      ~S(<path d="M4,11.2L12,4L20,11.2"/><path d="M6,10L6,20L18,20L18,10"/><path d="M10,20L10,14.5L14,14.5L14,20"/>),
    "praca" =>
      ~S(<path d="M4,19L20,19"/><path d="M6,15L10,15M7,15L7,19M9,15L9,19"/><path d="M16,12L16,19"/><ellipse cx="16" cy="9" rx="3" ry="3"/>),
    "lixeira" =>
      ~S(<path d="M4.5,7.5L19.5,7.5"/><path d="M9.5,7.5L9.5,5.2L14.5,5.2L14.5,7.5"/><path d="M6.5,7.5L7.5,20L16.5,20L17.5,7.5"/><path d="M8.1,13L15.9,13"/>),
    "privacidade" =>
      ~S(<path d="M8.5,10.5L8.5,8C8.5,6.07,10.07,4.5,12,4.5C13.93,4.5,15.5,6.07,15.5,8L15.5,10.5"/><rect x="5.5" y="10.5" width="13" height="9.5" rx="2"/>),
    "moradores" =>
      ~S(<path d="M3.6,19.5C3.6,16.2,6.1,14,9.2,14C12.3,14,14.8,16.2,14.8,19.5"/><path d="M16,14.6C18.6,14.8,20.4,16.8,20.4,19.5"/><ellipse cx="9.2" cy="8" rx="3.2" ry="3.2"/><ellipse cx="17" cy="9.2" rx="2.6" ry="2.6"/>),
    "servidor" =>
      ~S(<path d="M7,6.7L7.01,6.7"/><path d="M7,12L7.01,12"/><path d="M7,17.3L7.01,17.3"/><rect x="4" y="4.5" width="16" height="4.4" rx="1.4"/><rect x="4" y="9.8" width="16" height="4.4" rx="1.4"/><rect x="4" y="15.1" width="16" height="4.4" rx="1.4"/>),
    "pedidos" =>
      ~S(<path d="M4,5.5L20,5.5L20,18.5L4,18.5L4,5.5"/><path d="M4,13L8.2,13L9.6,15.4L14.4,15.4L15.8,13L20,13"/>),
    "dispositivos" =>
      ~S(<path d="M17.6,14.6L19.4,14.6"/><path d="M1,18.5L15,18.5"/><rect x="15.5" y="5" width="6" height="12" rx="1.6"/><rect x="2.5" y="9.5" width="11" height="8" rx="1.6"/>),
    "senha" =>
      ~S(<path d="M10.2,10.2L20,20"/><path d="M17.6,17.6L19.8,15.4"/><ellipse cx="7.8" cy="7.8" rx="3.4" ry="3.4"/>),
    "sair" => ~S(<path d="M13,4.5L5.5,4.5L5.5,19.5L13,19.5"/><path d="M13,12L21,12"/><path d="M18,9L21,12L18,15"/>)
  }

  @names Map.keys(@paths)

  @doc """
  Ícone outline do design system, SVG inline (`TainaWeb.Icons`).

      <.icon name="folder" />
      <.icon name="trash" size={20} class="text-error" />
  """
  attr :name, :string, required: true, values: @names
  attr :size, :integer, default: 24
  attr :class, :string, default: nil

  def icon(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      width={@size}
      height={@size}
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      class={["icon", @class]}
      aria-hidden="true"
    >
      {Phoenix.HTML.raw(path!(@name))}
    </svg>
    """
  end

  @doc "Nomes de ícone disponíveis (para validação em `attr :name, values: ...`)."
  def names, do: @names

  @doc "Markup interno (paths) do ícone. Levanta se o nome não existir."
  def path!(name), do: Map.fetch!(@paths, name)
end
