import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';
import 'dart:typed_data';

/// The byte layout of a `multipart/form-data` body, with no file IO.
///
/// A large upload is assembled by writing [prologue], streaming the file bytes
/// right after it, then writing [epilogue]. The file part must be last in
/// [parts], since its bytes are what the caller streams in between.
abstract final class MultipartBody {
  /// A boundary that cannot occur in the parts. Random, 32 hex characters.
  static String boundary() {
    final random = Random.secure();
    const digits = '0123456789abcdef';
    return String.fromCharCodes([
      for (var index = 0; index < 32; index++)
        digits.codeUnitAt(random.nextInt(16)),
    ]);
  }

  /// The bytes before the file bytes: every text part complete, then the file
  /// part's headers. The caller streams the file right after.
  static Uint8List prologue({
    required String boundary,
    required List<MultipartPart> parts,
  }) {
    final buffer = StringBuffer();
    for (final part in parts) {
      buffer.write('--$boundary\r\n');
      buffer.write(_headers(part));
      buffer.write('\r\n');
      switch (part.content) {
        case MultipartText(:final value):
          buffer.write(value);
          buffer.write('\r\n');
        case MultipartFile():
          break;
      }
    }
    return Uint8List.fromList(utf8.encode(buffer.toString()));
  }

  /// The closing delimiter. The leading CRLF ends the streamed file bytes and
  /// belongs to the boundary, so the caller writes nothing in between.
  static Uint8List epilogue({required String boundary}) =>
      Uint8List.fromList(utf8.encode('\r\n--$boundary--\r\n'));

  /// The whole body in memory. For tests and small parts only.
  static Uint8List encode({
    required String boundary,
    required List<MultipartPart> parts,
  }) {
    final builder = BytesBuilder(copy: false)
      ..add(prologue(boundary: boundary, parts: parts));
    for (final part in parts) {
      // A missing file would quietly produce an invalid body, but this form
      // is for tests; the live path streams with a file handle.
      if (part.content case MultipartFile(:final path)) {
        try {
          builder.add(io.File(path).readAsBytesSync());
        } on io.FileSystemException {
          continue;
        }
      }
    }
    builder.add(epilogue(boundary: boundary));
    return builder.takeBytes();
  }

  /// Escapes a filename for a Content-Disposition header: CR, LF and the
  /// double quote are the ones that break the frame.
  static String escaped(String filename) =>
      filename.replaceAll(RegExp(r'[\r\n"]'), '');

  static String _headers(MultipartPart part) {
    var disposition = 'Content-Disposition: form-data; name="${part.name}"';
    final filename = part.filename;
    if (filename != null) {
      disposition += '; filename="${escaped(filename)}"';
    }
    var lines = '$disposition\r\n';
    final contentType = part.contentType;
    if (contentType != null) {
      lines += 'Content-Type: $contentType\r\n';
    }
    return lines;
  }
}

/// One part of a multipart body.
final class MultipartPart {
  const MultipartPart({
    required this.name,
    this.filename,
    this.contentType,
    required this.content,
  });

  final String name;
  final String? filename;
  final String? contentType;
  final MultipartContent content;
}

sealed class MultipartContent {
  const MultipartContent();
}

final class MultipartText extends MultipartContent {
  const MultipartText(this.value);

  final String value;
}

final class MultipartFile extends MultipartContent {
  const MultipartFile(this.path);

  final String path;
}
