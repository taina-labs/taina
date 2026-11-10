import 'package:okena_core/src/api/instance_address.dart';
import 'package:okena_core/src/result.dart';

/// Where the box address lives between launches. The token is a credential
/// and belongs in platform secure storage; the address is not a secret and
/// lives here.
///
/// A UserDefaults/SharedPreferences backed implementation belongs to the app,
/// behind this contract.
abstract class HostStore {
  Future<InstanceAddress?> address();

  Future<TainaResult<void>> save(InstanceAddress address);

  Future<void> clear();
}

/// In memory, for tests and previews. Seeding it starts from an address
/// instead of a setup run.
final class InMemoryHostStore implements HostStore {
  InMemoryHostStore([InstanceAddress? address]) : _stored = address;

  InstanceAddress? _stored;

  @override
  Future<InstanceAddress?> address() async => _stored;

  @override
  Future<TainaResult<void>> save(InstanceAddress address) async {
    _stored = address;
    return const Ok<void>(null);
  }

  @override
  Future<void> clear() async {
    _stored = null;
  }
}
