# Falso positivo do backend gerado por `use Gettext.Backend`: o Dialyzer
# reclama de `call_without_opaque` ao chamar `Gettext.Plural.plural/2` com o
# tipo opaco `%Expo.PluralForms{}` do proprio Gettext/Expo. Nao e codigo nosso
# e some quando o Gettext relaxar a opacidade; ignoramos so este arquivo/aviso.
[
  {"lib/taina_web/gettext.ex", :call_without_opaque}
]
