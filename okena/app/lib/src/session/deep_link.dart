/// The box's link, in either of its two shapes, parsed once and purely.
///
/// The app's own scheme is `taina://convite/<token>?host=<host>` (the QR's)
/// and `taina://redefinir/<token>?host=<host>`. The web's link is pasted from
/// a message or a browser: `https://<host>/convite/<token>` or
/// `https://<host>/redefinir/<token>`.
///
/// The kind is the host component of the native scheme (or the first path
/// piece of the web one), the token is the path, and the box address rides in
/// the `host` query param or the URL's own host. Any other shape is not ours,
/// and the caller changes nothing when the parse comes back null.
final class DeepLink {
  const DeepLink({required this.kind, required this.token, required this.box});

  final DeepLinkKind kind;
  final String token;

  /// The box address as the link carries it, already trimmed; null when the
  /// link says nothing about which community it belongs to.
  final String? box;

  static DeepLink? parse(Uri uri) {
    switch (uri.scheme.toLowerCase()) {
      case 'taina':
        return _native(uri);
      case 'http':
      case 'https':
        return _web(uri);
      default:
        return null;
    }
  }

  /// The pasted form of the same link, trimmed of the whitespace a copy picks
  /// up along the way.
  static DeepLink? parsePasted(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    return parse(uri);
  }

  /// The app's own scheme: the kind is the host component, the token is the
  /// path, and the `host` query param carries the box address (url-encoded,
  /// so it reads back whole).
  static DeepLink? _native(Uri uri) {
    final kind = _kindOf(uri.host);
    if (kind == null) return null;

    // The path is /<token>: one piece, after the root. `Uri.path` keeps the
    // percent-encoding, so the token is decoded here, once.
    final path = uri.path;
    if (!path.startsWith('/')) return null;
    final raw = path.substring(1);
    if (raw.isEmpty || raw.contains('/')) return null;
    final token = _decode(raw);
    if (token == null || token.isEmpty) return null;

    final queried = uri.queryParameters['host']?.trim();
    final box = queried == null || queried.isEmpty ? null : queried;
    return DeepLink(kind: kind, token: token, box: box);
  }

  /// The web's own link, pasted: the box address is the URL's own scheme,
  /// host and port, the kind is the first path piece and the token is the
  /// second. The scheme is kept as it came: the pilot box answers plain
  /// http, and the address is shown with its caveat.
  static DeepLink? _web(Uri uri) {
    final pieces = [
      for (final piece in uri.pathSegments)
        if (piece.isNotEmpty) piece,
    ];
    if (pieces.length != 2) return null;
    final kind = _kindOf(pieces[0]);
    if (kind == null) return null;
    if (uri.host.isEmpty) return null;

    final box = Uri(
      scheme: uri.scheme.toLowerCase(),
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    ).toString();
    if (box.isEmpty) return null;
    return DeepLink(kind: kind, token: pieces[1], box: box);
  }

  static DeepLinkKind? _kindOf(String piece) {
    return switch (piece.toLowerCase()) {
      'convite' => DeepLinkKind.invite,
      'redefinir' => DeepLinkKind.reset,
      _ => null,
    };
  }

  static String? _decode(String value) {
    try {
      return Uri.decodeComponent(value);
    } on ArgumentError {
      return null;
    } on FormatException {
      return null;
    }
  }
}

/// The kind of link, which decides the screen and the token endpoint.
enum DeepLinkKind { invite, reset }
