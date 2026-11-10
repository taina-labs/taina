import 'dart:convert';
import 'dart:io';

import 'package:okena_core/okena_core.dart';

// Walks the fatia minima of the API against a live box, through the same
// client the app uses. That is the point: when a screen misbehaves, this says
// which layer is wrong, the box or the client.
//
// Reads by default. `--write` also creates a folder and uploads a file, and
// prints exactly what it left behind. The device token is never printed.
//
//     dart run okena_core:okena_smoke http://taina.yby --user ana --password segredo --write

Future<void> main(List<String> arguments) async {
  final typed = arguments
      .where((argument) => !argument.startsWith('--'))
      .firstOrNull;
  if (typed == null) {
    stderr.writeln(_usage);
    exit(2);
  }

  final parsed = InstanceAddress.parse(typed);
  final InstanceAddress address;
  switch (parsed) {
    case Ok(:final value):
      address = value;
    case Err():
      stdout.writeln(
        'endereco: recusado, veja o formato em taina.minhacasa.ts.net',
      );
      exit(1);
  }

  final host = InMemoryHostStore(address);
  final store = SessionStore(storage: InMemorySessionStorage());
  final api = LiveTainaApi(host: host, session: store);

  stdout.writeln(
    'caixa: ${address.display}'
    '${address.isCleartext ? ' (sem criptografia)' : ''}',
  );

  final instance = await api.instance();
  stdout.writeln(_line('instance', instance));
  switch (instance) {
    case Ok(value: final found) when !found.bootstrapped:
      stdout.writeln('a comunidade ainda nao existe nessa caixa');
      exit(1);
    case Err():
      exit(1);
    case Ok():
      break;
  }

  final user = _valueOf('--user', arguments);
  final password = _valueOf('--password', arguments);
  if (user != null && password != null) {
    final created = await api.createSession(
      username: user,
      password: password,
      deviceName: 'okena-smoke',
    );
    switch (created) {
      case Err(:final error):
        stdout.writeln('session: falhou (${error.message})');
        exit(1);
      case Ok(:final value):
        stdout.writeln(
          'session: aparelho "${value.device.name}" '
          'id=${value.device.publicId}, token criado e nao impresso',
        );
        await store.signIn(value);
    }
  }

  stdout.writeln(_line('me', await api.me()));
  stdout.writeln(_line('folders', await api.listFolders()));
  stdout.writeln(_line('contents (raiz)', await api.folderContents()));

  if (arguments.contains('--write')) {
    await _write(api);
  }

  stdout.writeln('fim');
}

/// Creates a folder, uploads a small text file, reads it back and asks for
/// its thumbnail, which a text file does not have.
Future<void> _write(LiveTainaApi api) async {
  final created = await api.createFolder(name: 'pasta-do-smoke');
  final Folder folder;
  switch (created) {
    case Ok(:final value):
      folder = value;
    case Err():
      stdout.writeln('write: criar pasta falhou');
      return;
  }
  stdout.writeln(
    'write: pasta criada ${folder.rkey} "${folder.name}" zona=${folder.zona.name}',
  );

  final body =
      'Arquivo criado pelo okena-smoke para provar upload, download '
      'e listagem.\n'
      'Se ele ainda esta na comunidade depois do teste, pode apagar.\n';
  final source = File('${Directory.systemTemp.path}/teste-do-smoke.txt');
  await source.writeAsString(body);

  final uploaded = await api.upload(
    filePath: source.path,
    name: 'teste-do-smoke.txt',
    mime: 'text/plain',
    folderRkey: folder.rkey,
  );
  final FileRecord file;
  switch (uploaded) {
    case Ok(:final value):
      file = value;
    case Err():
      stdout.writeln(_line('write: upload', uploaded));
      return;
  }
  stdout.writeln(
    'write: arquivo ${file.rkey} ${file.name} ${file.size} bytes '
    'sha256=${file.sha256.length >= 16 ? file.sha256.substring(0, 16) : file.sha256}...',
  );

  stdout.writeln(
    _line(
      'write: a pasta agora',
      await api.folderContents(folderRkey: folder.rkey),
    ),
  );

  switch (await api.download(rkey: file.rkey)) {
    case Err(:final error):
      stdout.writeln('write: download falhou (${error.message})');
    case Ok(:final value):
      final bytes = await File(value).readAsBytes();
      stdout.writeln(
        'write: download ${bytes.length} bytes, nome '
        '"${value.split('/').last}", igual ao enviado='
        '${utf8.decode(bytes) == body}',
      );
  }

  switch (await api.thumbnail(rkey: file.rkey, size: ThumbnailSize.sm)) {
    case Err(error: ApiError(:final code, :final status)):
      stdout.writeln(
        'write: miniatura recusada como esperado para um texto, '
        'code=$code status=$status',
      );
    case Err(:final error):
      stdout.writeln(
        'write: miniatura falhou de outro jeito (${error.message})',
      );
    case Ok(:final value):
      stdout.writeln(
        'write: miniatura ${value.length} bytes (inesperado para um texto)',
      );
  }
}

String _line<T>(String label, TainaResult<T> result) => switch (result) {
  Err(:final error) => '$label: falhou (${error.message})',
  Ok(:final value) => '$label: ${_describe(value)}',
};

String _describe(Object? value) => switch (value) {
  Me me =>
    '${me.ava.label} @${me.ava.username} papel=${me.ava.papel.name} '
        'comunidade=${me.tekoa.name}',
  List<Folder> folders =>
    '${folders.length}: '
        '${folders.map((folder) => '${folder.name}[${folder.zona.name}]').join(', ')}',
  FolderContents contents =>
    '${contents.folders.length} pasta(s), ${contents.items.length} arquivo(s), '
        'next_cursor=${contents.nextCursor ?? '-'}',
  Instance instance =>
    'bootstrapped=${instance.bootstrapped} '
        'comunidade=${instance.tekoa?.name ?? '-'} '
        'versao=${instance.version ?? '-'}',
  _ => '$value',
};

String? _valueOf(String flag, List<String> arguments) {
  final index = arguments.indexOf(flag);
  if (index < 0 || index + 1 >= arguments.length) return null;
  return arguments[index + 1];
}

const _usage =
    'uso: okena_smoke <endereco> [--user <usuario>] [--password <senha>] '
    '[--write]\n'
    '\n'
    '  <endereco>            por exemplo http://taina.yby\n'
    '  --user, --password    entra por token de dispositivo antes de listar\n'
    '  --write               cria a pasta pasta-do-smoke e sobe '
    'teste-do-smoke.txt';
