import 'package:okena_core/src/result.dart';
import 'package:okena_core/src/taina_error.dart';

/// The community's box address, validated before anything touches the
/// network. One box serves one community, so there is one address.
///
/// The person types where their box lives, and the app cannot know that at
/// build time, so `http` is accepted for any host. What it is not is silent:
/// [isCleartext] is what the screens read to say so.
final class InstanceAddress {
  const InstanceAddress._(this.url);

  /// Always scheme and host, no path, no query, no fragment.
  final Uri url;

  /// What a person typed, tightened: whitespace trimmed, https by default,
  /// one trailing slash dropped.
  static TainaResult<InstanceAddress> parse(String input) {
    var text = input.trim();
    if (text.isEmpty) {
      return const Err(InvalidAddressError(AddressProblem.empty));
    }
    if (!text.contains('://')) {
      text = 'https://$text';
    }
    if (text.endsWith('/') && !text.endsWith('://')) {
      text = text.substring(0, text.length - 1);
    }

    final Uri? components;
    try {
      components = Uri.tryParse(text);
    } on FormatException {
      return const Err(InvalidAddressError(AddressProblem.malformed));
    }
    if (components == null) {
      return const Err(InvalidAddressError(AddressProblem.malformed));
    }
    final scheme = components.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return const Err(InvalidAddressError(AddressProblem.unsupportedScheme));
    }
    if (components.host.isEmpty) {
      return const Err(InvalidAddressError(AddressProblem.malformed));
    }
    if (components.userInfo.isNotEmpty) {
      return const Err(InvalidAddressError(AddressProblem.malformed));
    }

    try {
      final clean = Uri(
        scheme: scheme,
        host: components.host,
        port: components.hasPort ? components.port : null,
      );
      return Ok(InstanceAddress._(clean));
    } on FormatException {
      return const Err(InvalidAddressError(AddressProblem.malformed));
    }
  }

  /// What a connect tries, in order: the address as typed, and, when the
  /// person did not type a scheme, the same host over plain http.
  ///
  /// The pilot box answers http, and a bare address must not dead-end on the
  /// https the parse assumed.
  static TainaResult<AddressCandidates> candidates(String input) {
    final parsed = parse(input);
    switch (parsed) {
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        final fallback = _schemeWasExplicit(input) ? null : value.overHttp();
        return Ok(AddressCandidates(primary: value, fallback: fallback));
    }
  }

  /// Rebuilds an address from the canonical string a [HostStore] persisted.
  /// The stored value was written by [parse], so this only re-validates it;
  /// the app's platform-backed store uses it on launch.
  static TainaResult<InstanceAddress> fromStored(String value) => parse(value);

  /// The same host one scheme down: the second candidate of a connect. An
  /// address that is already http has nowhere to go.
  InstanceAddress? overHttp() {
    if (url.scheme.toLowerCase() != 'https') return null;
    return InstanceAddress._(
      Uri(scheme: 'http', host: url.host, port: url.hasPort ? url.port : null),
    );
  }

  /// The person typed the scheme themselves; a bare host was completed with
  /// https by [parse].
  static bool _schemeWasExplicit(String input) => input.trim().contains('://');

  /// The host, for display: "taina.minhacasa.ts.net".
  String get display => url.host;

  /// The box answers without TLS. Shown wherever the host is, never hidden.
  bool get isCleartext => url.scheme.toLowerCase() == 'http';

  @override
  bool operator ==(Object other) =>
      other is InstanceAddress && other.url == url;

  @override
  int get hashCode => Object.hash(InstanceAddress, url);
}

/// The ordered attempts of one connect.
final class AddressCandidates {
  const AddressCandidates({required this.primary, required this.fallback});

  final InstanceAddress primary;
  final InstanceAddress? fallback;

  @override
  bool operator ==(Object other) =>
      other is AddressCandidates &&
      other.primary == primary &&
      other.fallback == fallback;

  @override
  int get hashCode => Object.hash(AddressCandidates, primary, fallback);
}
