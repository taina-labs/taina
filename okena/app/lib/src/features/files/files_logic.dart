import 'package:okena_core/okena_core.dart';

/// The browser's two lists: folders come complete, only files paginate.
final class FilesEntries {
  const FilesEntries({this.folders = const [], this.files = const []});

  final List<Folder> folders;
  final List<FileRecord> files;

  bool get isEmpty => folders.isEmpty && files.isEmpty;

  FilesEntries copyWith({List<Folder>? folders, List<FileRecord>? files}) {
    return FilesEntries(
      folders: folders ?? this.folders,
      files: files ?? this.files,
    );
  }
}

/// Pure decisions of the files feature: transitions over [FilesEntries], the
/// move filter, every pt-BR sentence and the mime lookup. No IO, no widgets,
/// so the screens and the ViewModels share one rule instead of repeating it.
abstract final class FilesLogic {
  static const String hashLabel = 'Assinatura do arquivo';
  static const String hashNote =
      'É como o Tainá confere que o arquivo está intacto.';
  static const String deleteFileMessage =
      'Vai para a lixeira. Dá para restaurar em até 30 dias.';
  static const String deleteFolderMessage =
      'A pasta e o que tem dentro vão para a lixeira. A pasta volta com tudo o que tem dentro.';
  static const String accessMotivo = 'Pedido de acesso pela tela do arquivo';
  static const String newFolderName = 'Nome da pasta';
  static const String newFolderHint =
      'As pastas nascem na sua casa. Publicar na praça da comunidade vem depois.';

  static FilesEntries entriesFrom(FolderContents contents) {
    return FilesEntries(folders: contents.folders, files: contents.items);
  }

  /// Creates a folder and puts it at the end of the list, where the server's
  /// own order would put it on the next refresh.
  static FilesEntries insertingFolder(FilesEntries entries, Folder folder) {
    return entries.copyWith(folders: [...entries.folders, folder]);
  }

  static FilesEntries insertingFile(FilesEntries entries, FileRecord file) {
    return entries.copyWith(files: [...entries.files, file]);
  }

  /// The next page joins the files; the folders do not paginate.
  static FilesEntries appending(FilesEntries entries, FolderContents page) {
    return entries.copyWith(files: [...entries.files, ...page.items]);
  }

  /// Puts the updated file where the old one was, order kept.
  static FilesEntries replacingFile(FilesEntries entries, FileRecord file) {
    final index = entries.files.indexWhere((item) => item.rkey == file.rkey);
    if (index < 0) return entries;
    final next = [...entries.files];
    next[index] = file;
    return entries.copyWith(files: next);
  }

  /// The uploaded files still in the casa carry the publish action: the
  /// reversal the flow almost hid. A file already in the praca, or uploaded
  /// in an earlier visit, shows nothing extra.
  static bool showsPublishAction(FileRecord file, Set<String> uploadedRkeys) {
    return file.zona == Zona.casa && uploadedRkeys.contains(file.rkey);
  }

  /// The destinations a move may offer: never the source itself, and, when
  /// the source is a folder, none of its descendants, where the move would
  /// close a cycle the box refuses. Pure over the readable list, walking each
  /// candidate's chain of parents. What the record cannot say is ownership:
  /// the wire carries no owner, so folders of other people still show and the
  /// box has the last word.
  static List<Folder> moveDestinations({
    required String sourceRkey,
    required bool isFolder,
    required List<Folder> folders,
  }) {
    final others = folders
        .where((folder) => folder.rkey != sourceRkey)
        .toList();
    if (!isFolder) return others;
    final byRkey = {for (final folder in folders) folder.rkey: folder};
    return others
        .where(
          (folder) => !_isDescendant(
            ancestorRkey: sourceRkey,
            folder: folder,
            byRkey: byRkey,
          ),
        )
        .toList();
  }

  /// True when the chain of parents of [folder] passes through the ancestor's
  /// rkey. The walk caps at the list's size, the same depth cap the box's own
  /// chain query uses: the graph is acyclic, and a corrupted answer cannot
  /// hang the sheet.
  static bool _isDescendant({
    required String ancestorRkey,
    required Folder folder,
    required Map<String, Folder> byRkey,
  }) {
    var parent = folder.folder;
    var steps = 0;
    while (parent != null && steps <= byRkey.length) {
      if (parent == ancestorRkey) return true;
      parent = byRkey[parent]?.folder;
      steps += 1;
    }
    return false;
  }

  /// The sentence an upload failure shows: quota has its own, and it does not
  /// promise what the box does not do: what is deleted still occupies space
  /// in the trash for up to 30 days, so "apague algo" would be a lie.
  static String uploadMessage(TainaError failure) {
    if (failure is ApiError && failure.isQuotaExceeded) {
      return 'O espaço da comunidade encheu. O que foi apagado segue '
          'ocupando espaço na lixeira por até 30 dias; se precisa de espaço '
          'agora, fale com quem cuida da comunidade.';
    }
    return failure.message;
  }

  static String zonaActionLabel(Zona zona) {
    return zona == Zona.casa ? 'Publicar na praça' : 'Tirar da praça';
  }

  /// Where an upload on this screen lands: the folder's zona, casa at the
  /// root. The destination is never silent, and in the casa the sentence
  /// names the way back to the praca.
  static String uploadDestinationMessage(Zona zona) {
    return zona == Zona.casa
        ? 'Vai para a sua casa: só você vê, até publicar na praça.'
        : 'Vai para a praça: todos os moradores vão ver.';
  }

  /// The kind a person reads for the raw mime, the web's `file_kind/1`.
  static String fileKind(String mime) {
    if (mime.startsWith('image/')) return 'Imagem';
    if (mime.startsWith('video/')) return 'Vídeo';
    if (mime.startsWith('audio/')) return 'Áudio';
    if (mime == 'application/pdf') return 'PDF';
    if (mime == 'application/zip') return 'ZIP';
    if (mime.startsWith('text/')) return 'Texto';
    return 'Arquivo';
  }

  /// "N arquivos" while a page is still missing, "N arquivos carregados" at
  /// the end of the list. The folders do not paginate, so the count talks
  /// about files.
  static String countLabel({required int count, required bool hasMore}) {
    final noun = count == 1 ? '1 arquivo' : '$count arquivos';
    if (!hasMore) return noun;
    return noun + (count == 1 ? ' carregado' : ' carregados');
  }

  static String zonaConfirmTitle(String name, Zona zona) {
    return zona == Zona.casa
        ? 'Publicar "$name" na praça?'
        : 'Tirar "$name" da praça?';
  }

  static String zonaConfirmBody(Zona zona) {
    return zona == Zona.casa
        ? 'Todos os moradores vão poder ver. Você pode tirar da praça quando '
              'quiser.'
        : 'Volta a ser só seu. Só você, e quem você deixar, vê de novo.';
  }

  /// The folder confirm says what the file confirm does not: only the folder
  /// goes to the praca, the files inside stay as they are.
  static String zonaFolderBody(String name, Zona zona) {
    if (zona == Zona.praca) return zonaConfirmBody(zona);
    return '${zonaConfirmBody(zona)} Só a pasta entra na praça. Os arquivos '
        'dentro dela continuam como estão.';
  }

  static String zonaConfirmPrimary(Zona zona) {
    return zona == Zona.casa ? 'Publicar' : 'Tirar da praça';
  }

  static String deleteFileTitle(String name) => 'Excluir "$name"?';

  static String deleteFolderTitle(String name) => 'Excluir a pasta "$name"?';

  /// The mime from the file's name, octet-stream when unknown. The picker
  /// hands a local copy and a name; the box wants the type beside the bytes.
  static String mimeFor(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) {
      return 'application/octet-stream';
    }
    final extension = name.substring(dot + 1).toLowerCase();
    return _mimes[extension] ?? 'application/octet-stream';
  }

  static const Map<String, String> _mimes = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'heic': 'image/heic',
    'heif': 'image/heif',
    'bmp': 'image/bmp',
    'svg': 'image/svg+xml',
    'tif': 'image/tiff',
    'tiff': 'image/tiff',
    'mp4': 'video/mp4',
    'm4v': 'video/x-m4v',
    'mov': 'video/quicktime',
    'avi': 'video/x-msvideo',
    'mkv': 'video/x-matroska',
    'webm': 'video/webm',
    'mp3': 'audio/mpeg',
    'm4a': 'audio/mp4',
    'wav': 'audio/wav',
    'aac': 'audio/aac',
    'ogg': 'audio/ogg',
    'flac': 'audio/flac',
    'pdf': 'application/pdf',
    'zip': 'application/zip',
    'gz': 'application/gzip',
    'tar': 'application/x-tar',
    'txt': 'text/plain',
    'md': 'text/markdown',
    'csv': 'text/csv',
    'json': 'application/json',
    'xml': 'text/xml',
    'html': 'text/html',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'epub': 'application/epub+zip',
    'ics': 'text/calendar',
  };
}
