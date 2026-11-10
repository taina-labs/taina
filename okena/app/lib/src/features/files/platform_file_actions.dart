import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import 'file_actions.dart';
import 'files_logic.dart';

/// The production [FileActions]: file_picker for the upload source,
/// share_plus for the sheet and open_filex for the viewer.
///
/// The picker is asked for a path only. Its new API hands a local copy on iOS
/// and Android, so [TainaApi.upload] streams the bytes from disk and no
/// `readAsBytes` happens here.
final class PlatformFileActions implements FileActions {
  const PlatformFileActions();

  @override
  Future<PickedFileOutcome> pick() async {
    try {
      final picked = await FilePicker.pickFile(type: FileType.any);
      if (picked == null) return const PickedFileCancelled();
      final path = picked.path;
      if (path == null) {
        return const PickedFileFailed(
          'Não deu para ler este arquivo do aparelho. Tente escolher outro.',
        );
      }
      return PickedFileSelected(
        PickedFile(
          path: path,
          name: picked.name,
          mime: FilesLogic.mimeFor(picked.name),
        ),
      );
    } on Object {
      return const PickedFileFailed(
        'Não deu para abrir o seletor de arquivos.',
      );
    }
  }

  @override
  Future<String?> share(String path, {String? subject}) async {
    try {
      final result = await SharePlus.instance.share(
        ShareParams(files: [XFile(path)], subject: subject, title: subject),
      );
      if (result.status == ShareResultStatus.unavailable) {
        return 'Não foi possível abrir o compartilhamento neste aparelho.';
      }
      return null;
    } on Object {
      return 'Não foi possível compartilhar o arquivo.';
    }
  }

  @override
  Future<String?> open(String path) async {
    try {
      final result = await OpenFilex.open(path);
      return switch (result.type) {
        ResultType.done => null,
        ResultType.noAppToOpen =>
          'Não há app neste aparelho para abrir este arquivo.',
        ResultType.fileNotFound =>
          'O arquivo baixado não foi encontrado. Baixe de novo.',
        ResultType.permissionDenied =>
          'O aparelho não deixou abrir este arquivo.',
        ResultType.error => 'Não foi possível abrir este arquivo.',
      };
    } on Object {
      return 'Não foi possível abrir este arquivo.';
    }
  }
}
