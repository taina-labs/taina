import 'package:flutter/services.dart';

/// The platform edge used to copy invite and password links.
abstract interface class MembersClipboard {
  Future<void> writeText(String text);
}

final class PlatformMembersClipboard implements MembersClipboard {
  const PlatformMembersClipboard();

  @override
  Future<void> writeText(String text) {
    return Clipboard.setData(ClipboardData(text: text));
  }
}
