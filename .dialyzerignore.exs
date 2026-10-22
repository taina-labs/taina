# Falso positivo do backend gerado por `use Gettext.Backend`: o Dialyzer
# reclama de `call_without_opaque` ao chamar `Gettext.Plural.plural/2` com o
# tipo opaco `%Expo.PluralForms{}` do proprio Gettext/Expo. Nao e codigo nosso
# e some quando o Gettext relaxar a opacidade; ignoramos so este arquivo/aviso.
[
  {"lib/taina_web/gettext.ex", :call_without_opaque},

  # Falso positivo do kernel (ypy 0.2): o `@spec` de `Ypy.Wire.File.json/1`
  # declara so `File.t()`, mas a funcao tem clausula para `%Folder{}` tambem
  # (arquivo e pasta tem a forma crua no MESMO modulo, que e a fonte unica do
  # fio). Ate o kernel corrigir a spec, as chamadas com pasta (o embrulho do
  # produto, `Serializer.folder/2`) acusam `invalid_contract`, `call` e o
  # `no_return` em cascata delas. Entradas estritas geradas por
  # `mix dialyzer --format ignore_file_strict` (arquivo + mensagem exata):
  # um aviso NOVO do mesmo tipo, em outra funcao, nao e mais mascarado.
  {"lib/taina_web/api/folder_controller.ex", "The created anonymous function has no local return."},
  {"lib/taina_web/api/folder_controller.ex", "Function folder_json/3 has no local return."},
  {"lib/taina_web/api/folder_controller.ex", "Function resolved_folder_json/2 has no local return."},
  {"lib/taina_web/api/serializer.ex", "Invalid type specification for function folder."},
  {"lib/taina_web/api/serializer.ex", "Function folder/2 has no local return."},
  {"lib/taina_web/api/serializer.ex", "The function call json will not succeed."}
]
