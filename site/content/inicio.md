# Arquivos e fotos guardados pela comunidade

O Tainá é um programa para uma comunidade guardar arquivos e fotos numa caixa que ela escolhe e cuida. A versão atual é **0.8.0**, publicada em 11 de novembro de 2026. O projeto ainda está em alfa. Este portal reúne guias, estado e um roteiro dos fluxos web.

<div class="hero__actions">
  <a class="btn btn--primary" href="/demonstracao/">Conhecer como funciona</a>
  <a class="btn btn--secondary" href="/estado/">Acompanhar o 1.0.0</a>
</div>

Já recebeu um convite? [Comece a usar o Tainá](/guias/comecar/).

## O que existe hoje

A versão web permite convidar moradores, guardar arquivos e fotos, separar conteúdos entre casa e praça, e ver a galeria, o mural e a saúde da comunidade. Há backup local com restauração. A versão web é a interface que pode ser apresentada hoje. O site não oferece um pacote do aplicativo para baixar. Antes de recomendar o aplicativo para uso por uma comunidade, é preciso concluir a validação em simulador iOS e emulador Android.

O Tainá roda numa caixa da comunidade ou num servidor alugado. Cada caixa atende uma comunidade só. Quem cuida da caixa é o zelador ou a zeladora; esse papel não dá acesso automático à casa de outra pessoa.

## O que o 1.0.0 pretende fechar

O recorte é capturar, guardar e recuperar arquivos e fotos:

- Selecionar fotos no aplicativo e usar a câmera.
- Espelhar o rolo de câmera do celular em uma direção, sempre para a casa. O espelho ainda não está implementado.
- Criar uma cópia cifrada fora da caixa, com kits de recuperação equivalentes. Esse backup externo também ainda não está implementado.
- Deixar mais claras as zonas e publicações na galeria e comprovar miniaturas JPEG e HEIC na versão empacotada do programa.

O backup local já existe e continua necessário. E2E, sincronização nos dois sentidos e propagação de exclusões não fazem parte deste escopo. Consulte o [estado e as evidências](/estado/) e o [roadmap completo](/estado/roadmap/).

## Casa e praça

Arquivos novos ficam na **casa**, espaço privado de quem os guardou. Só essa pessoa e quem ela autorizar podem abrir os arquivos pelo Tainá. A **praça** é o espaço comum: publicar ali significa que todos os moradores da comunidade podem ler. É possível tirar um arquivo da praça depois.

Essa separação é uma regra do programa, não criptografia. A pessoa que tem acesso de administrador ao sistema da caixa, chamada root, consegue ler os arquivos locais. A página de [privacidade](/privacidade/) explica esse limite.

## Por onde continuar

<div class="card-grid card-grid--2 portal-cards">
  <a class="feature-card portal-card" href="/demonstracao/">
    <span class="feature-card__tag">Roteiro em texto</span>
    <h2 class="feature-card__title">Como funciona</h2>
    <p class="feature-card__body">Leia o roteiro dos principais fluxos da versão web.</p>
  </a>
  <a class="feature-card portal-card" href="/estado/">
    <span class="feature-card__tag">Versão 0.8.0</span>
    <h2 class="feature-card__title">Estado atual</h2>
    <p class="feature-card__body">Veja o que passou por teste e o que continua pendente para o 1.0.0.</p>
  </a>
  <a class="feature-card portal-card" href="/guias/">
    <span class="feature-card__tag">Documentação</span>
    <h2 class="feature-card__title">Guias</h2>
    <p class="feature-card__body">Encontre os guias publicados e avisos sobre documentos que precisam ser atualizados.</p>
  </a>
  <a class="feature-card portal-card" href="/evolucao/">
    <span class="feature-card__tag">11 de novembro de 2026</span>
    <h2 class="feature-card__title">Evolução</h2>
    <p class="feature-card__body">Leia um resumo das mudanças recentes sem acompanhar o histórico técnico.</p>
  </a>
</div>

Para entender os termos, consulte o [glossário](/glossario/). Para saber quem mantém o projeto, veja [transparência](/transparencia/).
