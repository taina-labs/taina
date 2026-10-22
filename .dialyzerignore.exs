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
  # `no_return` em cascata delas.
  {"lib/taina_web/api/serializer.ex", :invalid_contract},
  {"lib/taina_web/api/serializer.ex", :call},
  {"lib/taina_web/api/serializer.ex", :no_return},
  {"lib/taina_web/api/folder_controller.ex", :no_return}
]
