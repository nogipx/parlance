import 'dart:async';

import 'package:parlance/src/participant/local.dart' show Participants;
import 'package:parlance/src/registry/registry.dart' show RawRegistry;
import 'package:parlance/src/remote/client.dart';
import 'package:parlance/testing.dart';
import 'package:parlance/tools.dart';
import 'package:rpc_dart/rpc_dart.dart';
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

  test('a call cancelled before its handler began runs when retried with '
      'its id: the id is not held to a call that did not run', () async {
    defineSlow(own);
    final me = host.participant(caller).raw;
    expect(
      await me.call(
        'slow.go',
        const {},
        id: 'c2',
        cancel: CancellationToken()..cancel(),
      ),
      isA<CallCancelled>(),
    );
    await host.settle();
    expect(ran, 0);
    final again = me.call('slow.go', const {}, id: 'c2');
    await host.settle();
    expect(ran, 1);
    release.complete();
    expect(await again, isA<CallDone<Object?>>());
  });

  test('a retry with the id while the handler runs late waits for its '
      'end, not for why the first caller stopped', () async {
    defineSlow(own);
    final me = host.participant(caller).raw;
    final cancel = CancellationToken();
    final first = me.call('slow.go', const {}, id: 'c3', cancel: cancel);
    await host.settle();
    cancel.cancel();
    expect(await first, isA<CallCancelled>());
    var answered = false;
    final again = me.call('slow.go', const {}, id: 'c3')
      ..then((_) => answered = true);
    await host.settle();
    expect(answered, isFalse, reason: 'its handler still runs');
    release.complete();
    expect(await again, isA<CallDone<Object?>>());
    expect(ran, 1);
  });

  test('a cancel while a guard is asked across a connection answers at '
      'once, and the call does not run', () async {
    defineSlow(own);
    final never = Completer<String?>();
    host.registry.addAskedGuard(
      'far-judge',
      (_) => never.future,
      timeout: const Duration(minutes: 1),
    );
    final me = host.participant(caller).raw;
    final cancel = CancellationToken();
    final r = me.call('slow.go', const {}, cancel: cancel);
    await host.settle();
    cancel.cancel();
    expect(await r.timeout(const Duration(seconds: 1)), isA<CallCancelled>());
    never.complete(null);
    await host.settle();
    expect(ran, 0);
  });

  test('a guest whose connection drops while its call runs: the call goes '
      'on untold, and its retry with the id, joined again, answers its '
      'end', () async {
    defineSlow(own);
    (ParlanceClient, RpcPeerEndpoint) link() {
      final (c, s) = RpcChannelTransport.pair();
      final responder = RpcPeerEndpoint(transport: s);
      host.registry.participant(caller).serve(responder);
      responder.start();
      final end = RpcPeerEndpoint(transport: c)..start();
      addTearDown(responder.close);
      addTearDown(end.close);
      return (ParlanceClient(end), end);
    }

    final (client, end) = link();
    unawaited(client.call('slow.go', const {}, id: 'd1'));
    await host.settle();
    expect(ran, 1);
    await end.close();
    await host.settle();
    expect(told, isEmpty, reason: 'a connection gone cancels nothing');

    final (again, _) = link();
    final r = again.call('slow.go', const {}, id: 'd1');
    release.complete();
    expect(await r, isA<CallDone<Object?>>());
    expect(ran, 1);
  });

  test(
    'a token given to many calls cancels the one still running only',
    () async {
      defineSlow(own);
      own.defineCommand(
        CommandDescriptor('slow.quick', callers: Callers.anyone),
        (_) => 'done',
      );
      final me = host.participant(caller).raw;
      final screen = CancellationToken();
      for (var i = 0; i < 3; i++) {
        expect(
          await me.call('slow.quick', const {}, cancel: screen),
          isA<CallDone<Object?>>(),
        );
      }
      final r = me.call('slow.go', const {}, cancel: screen);
      await host.settle();
      screen.cancel();
      expect(await r, isA<CallCancelled>());
      release.complete();
    },
  );

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
