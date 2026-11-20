import 'package:flutter/foundation.dart';
import 'package:okena_core/okena_core.dart';

import '../../session/deep_link.dart';
import '../../session/session_model.dart';

typedef ConfirmCommunitySwitch = Future<bool> Function(
  InstanceAddress nextAddress,
  String communityName,
);

/// The submitted value after it has been normalized to the session's link
/// boundary.
final class InvitePasteRequest {
  const InvitePasteRequest({
    required this.link,
    required this.address,
    required this.kind,
    required this.token,
  });

  final String link;
  final InstanceAddress? address;
  final DeepLinkKind kind;
  final String token;
}

/// State for the route-composable invite paste screen.
final class InvitePasteViewModel extends ChangeNotifier {
  InvitePasteViewModel({required this.session});

  final SessionModel session;

  String? problem;
  bool opening = false;

  void clearProblem() {
    if (problem == null) return;
    problem = null;
    notifyListeners();
  }

  Future<void> open(
    String text, {
    String address = '',
    ConfirmCommunitySwitch? confirmCommunitySwitch,
  }) async {
    final request = prepare(
      text,
      address: address,
      hasSavedHost: session.host != null,
    );
    if (request == null) {
      problem = problemFor(
        text,
        address: address,
        hasSavedHost: session.host != null,
      );
      notifyListeners();
      return;
    }

    final saved = session.host;
    final next = request.address;
    if (saved != null && next != null && communityChanged(saved, next)) {
      if (confirmCommunitySwitch == null) {
        problem = 'Confirme a troca de comunidade para continuar.';
        notifyListeners();
        return;
      }
      opening = true;
      problem = null;
      notifyListeners();
      final probe = await session.probeAddress(next);
      final communityName = destinationCommunityName(
        next,
        probe.value?.tekoa?.name,
      );
      if (!await confirmCommunitySwitch(next, communityName)) {
        opening = false;
        notifyListeners();
        return;
      }
    }

    opening = true;
    problem = null;
    notifyListeners();
    problem = await session.openPastedInvite(request.link);
    opening = false;
    notifyListeners();
  }

  static InvitePasteRequest? prepare(
    String text, {
    required String address,
    required bool hasSavedHost,
  }) {
    final raw = text.trim();
    if (raw.isEmpty) return null;

    final parsed = DeepLink.parsePasted(raw);
    if (parsed != null) {
      final InstanceAddress? parsedAddress;
      if (parsed.box == null) {
        if (hasSavedHost) {
          parsedAddress = null;
        } else {
          parsedAddress = _address(address);
          if (parsedAddress == null) return null;
        }
      } else {
        parsedAddress = _address(parsed.box!);
        if (parsedAddress == null) return null;
      }
      final link = parsedAddress == null || parsed.box != null
          ? raw
          : _nativeLink(parsed.kind, parsed.token, parsedAddress);
      return InvitePasteRequest(
        link: link,
        address: parsedAddress,
        kind: parsed.kind,
        token: parsed.token,
      );
    }

    if (!_bareToken.hasMatch(raw)) return null;
    final InstanceAddress? parsedAddress;
    if (hasSavedHost) {
      parsedAddress = null;
    } else {
      parsedAddress = _address(address);
      if (parsedAddress == null) return null;
    }
    return InvitePasteRequest(
      link: parsedAddress == null
          ? _nativeLink(DeepLinkKind.invite, raw, null)
          : _nativeLink(DeepLinkKind.invite, raw, parsedAddress),
      address: parsedAddress,
      kind: DeepLinkKind.invite,
      token: raw,
    );
  }

  static String? problemFor(
    String text, {
    required String address,
    required bool hasSavedHost,
  }) {
    final raw = text.trim();
    if (raw.isEmpty) {
      return 'Cole o link ou o código do convite.';
    }
    if (DeepLink.parsePasted(raw) != null) {
      final parsed = DeepLink.parsePasted(raw)!;
      if (parsed.box == null && !hasSavedHost && address.trim().isEmpty) {
        return 'O código sozinho não diz qual é a comunidade.';
      }
      if (parsed.box != null || !hasSavedHost) {
        final target = parsed.box ?? address;
        final parsedAddress = _address(target);
        if (parsedAddress == null) {
          return 'Confira o endereço da comunidade.';
        }
      }
    } else if (_bareToken.hasMatch(raw) && !hasSavedHost) {
      if (address.trim().isEmpty) {
        return 'O código sozinho não diz qual é a comunidade.';
      }
      if (_address(address) == null) {
        return 'Confira o endereço da comunidade.';
      }
    } else if (!_bareToken.hasMatch(raw)) {
      return 'Este link não pôde ser lido. Confira se copiou o link inteiro, '
          'do começo ao fim.';
    }
    return 'Este link não pôde ser lido. Confira se copiou o link inteiro, '
        'do começo ao fim.';
  }

  static bool communityChanged(InstanceAddress saved, InstanceAddress next) =>
      saved != next;

  static String destinationCommunityName(
    InstanceAddress address,
    String? communityName,
  ) {
    final name = communityName?.trim();
    return name == null || name.isEmpty ? address.display : name;
  }

  static final RegExp _bareToken = RegExp(r'^[A-Za-z0-9_-]+$');

  static InstanceAddress? _address(String value) {
    final result = InstanceAddress.parse(value);
    return result.value;
  }

  static String _nativeLink(
    DeepLinkKind kind,
    String token,
    InstanceAddress? address,
  ) {
    final schemeKind = switch (kind) {
      DeepLinkKind.invite => 'convite',
      DeepLinkKind.reset => 'redefinir',
    };
    return Uri(
      scheme: 'taina',
      host: schemeKind,
      path: '/$token',
      queryParameters: address == null
          ? null
          : {'host': address.url.toString()},
    ).toString();
  }
}
