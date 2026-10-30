import 'dart:async';

import 'package:parlance/testing.dart';
import 'package:parlance/tools.dart';
import 'package:test/test.dart';

/// A caller may cancel its call (`cancel:`): it stops waiting, answered
/// `cancelled`. Not that it did not happen: a handler that began is told
/// (`expired`), and what it does stands, its end recorded late, as when
/// the deadline passes; one cancelled before it went does not run.
const owner = Principal('owner');
const caller = Principal('caller');

void main() {
  late TestHost host;
  late IRawParticipant own;
  late Completer<void> release;
  late List<String> told;
  late int ran;

  setUp(() {
    host = TestHost();
    own = host.participant(owner, vocabularies: [WordSet.open('slow')]).raw;
    release = Completer();
    told = [];
    ran = 0;
  });
  tearDown(() => host.dispose());

  /// A command [name] that answers once [release] completes, telling when
  /// its call expired.
  void defineSlow(IRawParticipant p, [String name = 'slow.go']) =>
      p.defineCommand(CommandDescriptor(name, callers: Callers.anyone), (
        call,
      ) async {
        ran++;
        unawaited(call.expired.whenCancelled.then((_) => told.add(call.id)));
        await release.future;
        return 'went';
      });

  test('a call cancelled while its handler runs answers cancelled; the '
      'handler is told, and its end answers a retry with the id', () async {
    defineSlow(own);
    final me = host.participant(caller).raw;
    final cancel = CancellationToken();
    final r = me.call('slow.go', const {}, id: 'c1', cancel: cancel);
    await host.settle();
    cancel.cancel();
    expect(await r, isA<CallCancelled>());
    await host.settle();
    expect(told, hasLength(1), reason: 'its handler was told');

    release.complete();
    await host.settle();
    expect(
      await me.call('slow.go', const {}, id: 'c1'),
      isA<CallDone<Object?>>(),
    );
    expect(ran, 1, reason: 'it ran once');
    expect(host.calls.lastWhere((c) => c.command == 'slow.go').late, isTrue);
  });

  test('a call cancelled before it is made does not run', () async {
    defineSlow(own);
    final me = host.participant(caller).raw;
    expect(
      await me.call('slow.go', const {}, cancel: CancellationToken()..cancel()),
      isA<CallCancelled>(),
    );
    expect(ran, 0);
  });

  test('a query cancelled answers cancelled', () async {
    own.defineQuery(
      QueryDescriptor(
        'slow.look',
        returns: const TextType(),
        askers: Callers.anyone,
      ),
      (call) => release.future.then((_) => 'seen'),
    );
    final me = host.participant(caller).raw;
    final cancel = CancellationToken();
    final r = me.call('slow.look', const {}, cancel: cancel);
    cancel.cancel();
    expect(await r, isA<CallCancelled>());
    release.complete();
  });

  test('across a connection, a call to the host cancelled answers '
      'cancelled, and the host\'s handler is told', () async {
    defineSlow(own);
    final guest = (await host.join(caller)).raw;
    final cancel = CancellationToken();
    final r = guest.call('slow.go', const {}, cancel: cancel);
    await host.settle();
    expect(ran, 1);
    cancel.cancel();
    expect(await r, isA<CallCancelled>());
    await host.settle();
    expect(told, hasLength(1), reason: 'the cancel went across');
    release.complete();
  });

  test('across a connection, a call cancelled before it went does not '
      'run', () async {
    defineSlow(own);
    final guest = (await host.join(caller)).raw;
    expect(
      await guest.call(
        'slow.go',
        const {},
        cancel: CancellationToken()..cancel(),
      ),
      isA<CallCancelled>(),
    );
    await host.settle();
    expect(ran, 0);
  });

  test('a call the host\'s caller cancels tells the handler of the guest '
      'serving it', () async {
    final guest = (await host.join(
      const Principal('guest'),
      vocabularies: [WordSet.open('far')],
    )).raw;
    defineSlow(guest, 'far.go');
    await guest.settle();
    final me = host.participant(caller).raw;
    final cancel = CancellationToken();
    final r = me.call('far.go', const {}, cancel: cancel);
    await host.settle();
    expect(ran, 1);
    cancel.cancel();
    expect(await r, isA<CallCancelled>());
    await host.settle();
    expect(told, hasLength(1), reason: 'the guest heard it expired');
    release.complete();
    await host.settle();
  });
}
