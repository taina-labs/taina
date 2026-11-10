import 'package:flutter/foundation.dart';

import '../../session/session_model.dart';

/// The paste field of the invite link, on the two screens where the app can
/// still be pointed at a community.
///
/// The link arrives as text or as a QR shot, in either of the box's two
/// shapes, and goes through the same deep-link path a tapped link takes. What
/// cannot open comes back as a sentence under the field.
final class InvitePasteViewModel extends ChangeNotifier {
  InvitePasteViewModel({required this.session});

  final SessionModel session;

  String? problem;

  Future<void> open(String text) async {
    problem = await session.openPastedInvite(text);
    notifyListeners();
  }
}
