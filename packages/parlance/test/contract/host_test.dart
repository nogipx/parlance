import 'package:parlance/app.dart';
import 'package:rpc_dart/rpc_dart.dart';
import 'package:test/test.dart';

/// What a host's and a guest's `main` do, with `app.dart` alone: a host
/// serves a guest, the guest's owner serves its command there, a part of
/// the host calls it, and the session ends with its connection.
enum _Command<P, R> implements ICommandWord<P, R> {
  ping<(), String>('echo.ping', _none, Plain(TextType()));

  const _Command(this.name, this.params, this.returns);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<R>? returns;
}

const _none = RecordShape<()>({}, to: _noJson, from: _fromNone);
Map<String, Object?> _noJson(() _) => const {};
() _fromNone(Map<String, Object?> _) => ();

final class _Echo implements IOwner {
  _Echo() {
    IOwner.made(
      this,
      define: (p) => p
          .command(_Command.ping)
          .serve(
            (_) => 'pong to ${caller!.kind}',
            callers: const Callers({'user': Access.allow}),
          ),
    );
  }
}

void main() {
  test('a host serves a guest; the session ends with its connection', () async {
    final host = Host();
    addTearDown(host.dispose);
    final (g, h) = RpcChannelTransport.memoryPair();
    final atHost = RpcPeerEndpoint(transport: h);
    final session = host.serve(
      atHost,
      const Principal('guest', 'echo'),
      vocabularies: [WordSet.open('echo')],
    );
    atHost.start();
    expect(session.who, const Principal('guest', 'echo'));

    final atGuest = RpcPeerEndpoint(transport: g)..start();
    final guest = await Guest.over(atGuest);
    await guest.attach({'it': _Echo()});

    final user = host.participant(const Principal('user', 'ann'));
    await user.settle();
    final r = await user.command(_Command.ping).call(());
    expect((r as CallDone<String>).value, 'pong to user');

    var ended = false;
    session.ended.then((_) => ended = true);
    await atGuest.close();
    await session.ended.timeout(const Duration(seconds: 2));
    expect(ended, isTrue);
    expect(user.status('echo.ping'), isA<WordMissing>());
    guest.dispose();
    await atHost.close();
  });
}
