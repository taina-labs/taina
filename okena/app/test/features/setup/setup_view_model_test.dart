import 'package:flutter_test/flutter_test.dart';
import 'package:okena_app/src/features/setup/setup_view_model.dart';
import 'package:okena_app/src/session/session_state.dart';
import 'package:okena_core/okena_core.dart';

import '../../session/support/session_support.dart';

void main() {
  test('typedCleartext follows the address being typed', () {
    final composed = makeSession(state: const SessionNeedsInstance());
    final model = SetupViewModel(session: composed.model);

    expect(model.typedCleartext('http://box.local'), isTrue);
    expect(model.typedCleartext('box.local'), isFalse);
    expect(model.typedCleartext(''), isFalse);
  });

  test('an empty address is the field error and drops the spinner', () async {
    final composed = makeSession(state: const SessionNeedsInstance());
    final model = SetupViewModel(session: composed.model);

    await model.connect('   ');

    expect(model.failure, const InvalidAddressError(AddressProblem.empty));
    expect(model.probing, isFalse);
  });

  test('an unreachable box keeps the setup with its own sentence', () async {
    final composed = makeSession(
      state: const SessionNeedsInstance(),
      probe: (address) async => const Err(NetworkError('down')),
    );
    final model = SetupViewModel(session: composed.model);

    await model.connect('box.local');

    expect(model.failure, isA<NetworkError>());
    expect(SetupViewModel.unreachable(model.failure!), isTrue);
    expect(composed.model.state, isA<SessionNeedsInstance>());
  });

  test('a box without a community stays and shows the instance', () async {
    final composed = makeSession(
      state: const SessionNeedsInstance(),
      probe: (address) async =>
          const Ok(Instance(bootstrapped: false, tekoa: null, version: null)),
    );
    final model = SetupViewModel(session: composed.model);

    await model.connect('box.local');

    expect(model.failure, isNull);
    expect(model.instance?.bootstrapped, isFalse);
    expect(model.probing, isFalse);
  });
}
