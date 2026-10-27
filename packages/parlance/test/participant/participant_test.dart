import 'dart:async';

import 'package:parlance/participant.dart';
import 'package:parlance/registry.dart';
import 'package:test/test.dart';

const orders = Principal('module', 'orders');
const cart = Principal('module', 'cart');
const someone = Principal('viewer', 'v1');

typedef Order = ({String id, String status});

final _order = RecordShape<Order>(
  {'id': Part(Plain(TextType())), 'status': Part(Plain(TextType()))},
  to: (o) => {'id': o.id, 'status': o.status},
  from: (m) => (id: m['id']! as String, status: m['status']! as String),
);

enum OrderState<T> implements IStateWord<T> {
  last<Order>('orders.last');

  const OrderState(this.name);
  @override
  final String name;
  @override
  Shape<T> get shape => _order as Shape<T>;
  @override
  String? get key => null;
}

enum OrderCommand<P, R> implements ICommandWord<P, R> {
  place<Order, String>('orders.place');

  const OrderCommand(this.name);
  @override
  final String name;
  @override
  RecordShape<P> get params => _order as RecordShape<P>;
  @override
  Shape<R>? get returns => const Plain(TextType()) as Shape<R>;
}

enum OrderFact<T> implements IFactWord<T> {
  placed<Order>('orders.placed');

  const OrderFact(this.name);
  @override
  final String name;
  @override
  Shape<T> get shape => _order as Shape<T>;
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late Registry r;

  setUp(() => r = Registry());
  tearDown(() => r.dispose());

  /// The orders module: its state, a command that writes it and says a
  /// fact, callable by the cart.
  LocalParticipant ordersModule() {
    final p = r.participant(orders, vocabularies: [WordSet.open('orders')]);
    final last = p.state(OrderState.last).define();
    final placed = p.fact(OrderFact.placed).define();
    p.command(OrderCommand.place).define((c) {
      last.set(c.params, cause: c.causeFor(orders));
      placed.emit(c.params, cause: c.causeFor(orders));
      return c.params.id;
    }, callers: Callers.only(['module/cart']));
    return p;
  }

  group('a participant defines', () {
    test(
      'words in its namespaces, used by others through typed words',
      () async {
        ordersModule();
        final c = r.participant(cart, vocabularies: [WordSet.open('cart')]);
        final heard = <Order>[];
        final sub = c
            .fact(OrderFact.placed)
            .stream
            .listen((f) => heard.add(f.payload));
        final done = await c.command(OrderCommand.place).call((
          id: 'o1',
          status: 'new',
        ));
        await settle();
        expect(done, isA<CallDone<String>>());
        expect((done as CallDone<String>).value, 'o1');
        expect(c.state(OrderState.last).read(), (id: 'o1', status: 'new'));
        expect(heard, [(id: 'o1', status: 'new')]);
        final change = r.lastChange('orders.last')!;
        expect(change.cause.by, orders, reason: 'written as the owner');
        expect(r.recent('orders.placed').single.cause.by, orders);
        await sub.cancel();
      },
    );

    test('nothing outside its namespaces', () {
      final p = r.participant(orders, vocabularies: [WordSet.open('orders')]);
      expect(() => p.state(_Other.flag).define(), throwsA(isA<StateError>()));
      expect(r.stateDescriptor('cart.flag'), isNull);
      final none = r.participant(const Principal('module', 'x'));
      expect(
        () => none.state(OrderState.last).define(),
        throwsA(isA<StateError>()),
        reason: 'no namespace, no words',
      );
    });

    test('no command that sets a state of another', () {
      r
          .participant(cart, vocabularies: [WordSet.open('cart')])
          .state(_Other.flag)
          .define();
      final p = r.participant(orders, vocabularies: [WordSet.open('orders')]);
      expect(
        () => p.defineCommand(
          CommandDescriptor(
            'orders.flag',
            params: ObjectType({'on': Field(BoolType())}),
            callers: Callers({'*': Access.allow}),
            sets: Sets('cart.flag', value: 'on'),
          ),
          (_) {},
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('only as far as its rights let it', () {
      final p = r.participant(
        orders,
        vocabularies: [WordSet.open('orders')],
        rights: ParticipantRights(
          define: (_, d) => d is FactDescriptor ? 'no facts' : null,
        ),
      );
      p.state(OrderState.last).define();
      expect(
        () => p.fact(OrderFact.placed).define(),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('namespaces', () {
    test('are one participant\'s, until it goes', () {
      final a = r.participant(orders, vocabularies: [WordSet.open('orders')]);
      expect(
        () => r.participant(cart, vocabularies: [WordSet.open('orders')]),
        throwsA(isA<StateError>()),
      );
      expect(
        () =>
            r.participant(cart, vocabularies: [WordSet.open('orders.archive')]),
        throwsA(isA<StateError>()),
        reason: 'inside another\'s',
      );
      a.dispose();
      expect(
        r.participant(cart, vocabularies: [WordSet.open('orders')]).namespaces,
        {'orders'},
      );
    });
  });

  group('a participant acts as itself', () {
    test('its calls are by it, and its callers rights hold', () async {
      ordersModule();
      final stranger = r.participant(someone);
      final refused = await stranger.command(OrderCommand.place).call((
        id: 'o2',
        status: 'new',
      ));
      expect(refused, isA<CallRefused>());
      expect((refused as CallRefused).code, Refusal.notPermitted);
      expect(stranger.status('orders.place'), const WordNotPermitted());
    });

    test('a write, a call or a fact as another is refused', () async {
      final p = ordersModule();
      expect(
        () => p.call('orders.place', {}, cause: const Cause(someone)),
        throwsA(isA<StateError>()),
      );
      final q = r.participant(cart, vocabularies: [WordSet.open('cart')]);
      final flag = q.state(_Other.flag).define();
      expect(
        () => flag.set(true, cause: const Cause(someone)),
        throwsA(isA<StateError>()),
      );
    });

    test('speaks for another only when its rights let it', () async {
      final mute = r.participant(
        orders,
        vocabularies: [WordSet.open('orders')],
      );
      final a = mute.fact(OrderFact.placed).define();
      expect(
        () => a.emit((id: 'o', status: 'new'), cause: const Cause(someone)),
        throwsA(isA<StateError>()),
      );
      mute.dispose();
      final voice = r.participant(
        orders,
        vocabularies: [WordSet.open('orders')],
        rights: ParticipantRights(
          speakFor: (_, by, _) => by.kind == 'viewer' ? null : 'viewers only',
        ),
      );
      voice.fact(OrderFact.placed).define().emit((
        id: 'o',
        status: 'new',
      ), cause: const Cause(someone));
      expect(r.recent('orders.placed').single.cause.by, someone);
    });

    test('says an open fact of another only when its rights let it', () {
      r
          .participant(orders, vocabularies: [WordSet.open('orders')])
          .fact(OrderFact.placed)
          .define(open: true);
      expect(
        () => r.participant(cart).fact(OrderFact.placed).producer(),
        throwsA(isA<StateError>()),
      );
      final producer = r
          .participant(
            const Principal('module', 'sync'),
            rights: ParticipantRights(produce: (_, _) => null),
          )
          .fact(OrderFact.placed)
          .producer();
      expect(producer.emit((id: 'o', status: 'synced')), isTrue);
    });

    test('reads only what it may', () {
      final p = r.participant(orders, vocabularies: [WordSet.open('orders')]);
      p
          .state(OrderState.last)
          .define(readers: Callers.only(['module/orders']))
          .set((id: 'o', status: 'new'));
      final c = r.participant(cart);
      expect(c.state(OrderState.last).read(), isNull);
      expect(c.status('orders.last'), const WordNotPermitted());
      expect(p.state(OrderState.last).read(), (id: 'o', status: 'new'));
    });
  });

  group('access by default', () {
    test('its words take it when they say nothing; a word\'s own replaces '
        'it whole', () async {
      final p = r.participant(
        orders,
        vocabularies: [WordSet.open('orders')],
        access: WordAccess(
          read: Callers.only(['module/orders', 'module/cart']),
          call: Callers.only(['module/cart']),
        ),
      );
      p.state(OrderState.last).define();
      p.fact(OrderFact.placed).define(readers: Callers.only(['module/orders']));
      p.command(OrderCommand.place).define((c) => c.params.id);

      expect(r.stateDescriptor('orders.last')!.readers!.rules.keys, {
        'module/orders',
        'module/cart',
      });
      expect(r.factDescriptor('orders.placed')!.readers!.rules.keys, {
        'module/orders',
      }, reason: 'its own, not merged');
      final c = r.participant(cart);
      final stranger = r.participant(someone);
      expect(c.status('orders.last'), const WordReady());
      expect(stranger.status('orders.last'), const WordNotPermitted());
      expect(c.status('orders.placed'), const WordNotPermitted());
      expect(
        (await c.command(OrderCommand.place).call((id: 'o', status: 'n'))).ok,
        isTrue,
      );
      expect(stranger.status('orders.place'), const WordNotPermitted());
    });

    test('a command with no callers anywhere is refused at once', () {
      final p = r.participant(orders, vocabularies: [WordSet.open('orders')]);
      expect(
        () => p.command(OrderCommand.place).define((c) => c.params.id),
        throwsArgumentError,
      );
      expect(r.commandDescriptor('orders.place'), isNull);
    });

    test('without it, a state is everyone\'s to read', () {
      r
          .participant(orders, vocabularies: [WordSet.open('orders')])
          .state(OrderState.last)
        ..define()
        ..read();
      expect(r.stateDescriptor('orders.last')!.readers, isNull);
    });
  });

  group('parts', () {
    test('a selector names the parts of what it names; the nearest wins', () {
      final sync = orders.child('sync');
      expect(sync, const Principal('module', 'orders/sync'));
      expect(sync.child('push').selector, 'module/orders/sync/push');
      expect(sync.isWithin(orders), isTrue);
      expect(orders.isWithin(sync), isFalse);
      final callers = Callers({
        'module/orders': Access.allow,
        'module/orders/sync': Access.deny,
      });
      expect(callers.allows(orders.child('ui')), isTrue, reason: 'its whole');
      expect(callers.allows(sync), isFalse, reason: 'its own rule');
      expect(callers.allows(sync.child('push')), isFalse, reason: 'nearest');
      expect(callers.allows(cart), isFalse);
      expect(() => orders.child('Sync'), throwsArgumentError);
    });

    test('a part writes, says and calls as itself; a cause of its whole is '
        'its own, a sibling\'s is refused', () async {
      ordersModule();
      final c = r.participant(cart, vocabularies: [WordSet.open('cart')]);
      final ui = c.child('ui');
      final flag = ui.state(_Other.flag).define()..set(true);
      expect(r.lastChange('cart.flag')!.cause.by, cart.child('ui'));
      flag.set(false, cause: const Cause(cart));
      expect(r.lastChange('cart.flag')!.cause.by, cart.child('ui'));
      expect(
        () => flag.set(true, cause: Cause(cart.child('sync'))),
        throwsA(isA<NotPermitted>()),
      );
      final records = <CallRecord>[];
      final sub = r.calls.listen(records.add);
      final done = await ui.command(OrderCommand.place).call((
        id: 'o9',
        status: 'new',
      ));
      await settle();
      expect(done.ok, isTrue, reason: 'module/cart names its parts too');
      expect(records.single.cause.by, cart.child('ui'), reason: 'the record');
      await sub.cancel();
    });

    test('a part\'s guard judges its own commands only', () async {
      final p = r.participant(orders, vocabularies: [WordSet.open('orders')]);
      final a = p.child('a');
      final b = p.child('b');
      a.defineCommand(
        CommandDescriptor(
          'orders.a',
          callers: const Callers({'*': Access.allow}),
        ),
        (_) {},
      );
      b.defineCommand(
        CommandDescriptor(
          'orders.b',
          callers: const Callers({'*': Access.allow}),
        ),
        (_) {},
      );
      a.addGuard('orders.no', (_) => 'no');
      expect((await r.call('orders.a', {}, by: cart)).ok, isFalse);
      expect((await r.call('orders.b', {}, by: cart)).ok, isTrue);
    });

    test('a part going withdraws its words only; its whole going withdraws '
        'its parts', () {
      final p = r.participant(orders, vocabularies: [WordSet.open('orders')]);
      final a = p.child('a');
      a.state(OrderState.last).define();
      p.child('b').fact(OrderFact.placed).define();
      a.dispose();
      expect(r.stateDescriptor('orders.last'), isNull);
      expect(r.factDescriptor('orders.placed'), isNotNull);
      p.dispose();
      expect(r.factDescriptor('orders.placed'), isNull);
    });
  });

  test('its guards judge calls of its own commands only', () async {
    final p = ordersModule();
    p.addGuard('orders.no-o3', (c) => c.params['id'] == 'o3' ? 'no o3' : null);
    final c = r.participant(cart, vocabularies: [WordSet.open('cart')]);
    var flagged = 0;
    c.defineCommand(
      CommandDescriptor(
        'cart.add',
        params: ObjectType({'id': Field(TextType())}),
        callers: Callers({'*': Access.allow}),
      ),
      (_) => flagged++,
    );
    final denied = await c.call('orders.place', {'id': 'o3', 'status': 'new'});
    expect((denied as CallRefused).code, Refusal.denied);
    expect((await c.call('cart.add', {'id': 'o3'})).ok, isTrue);
    expect(flagged, 1, reason: 'the guard does not judge another\'s command');
  });

  test('watching a state starts with its value now', () async {
    final p = r.participant(orders, vocabularies: [WordSet.open('orders')]);
    final last = p.state(OrderState.last).define()
      ..set((id: 'o1', status: 'new'));
    final seen = <Order?>[];
    final sub = r
        .participant(cart)
        .state(OrderState.last)
        .watch()
        .listen(seen.add);
    await settle();
    last.set((id: 'o1', status: 'paid'));
    await settle();
    expect(seen, [(id: 'o1', status: 'new'), (id: 'o1', status: 'paid')]);
    await sub.cancel();
  });

  test('going, it withdraws all it defined; others see the words missing', () {
    final p = ordersModule();
    p.addGuard('orders.g', (_) => null);
    p.registerKind(EntityKind('order', list: () => const []));
    final c = r.participant(cart);
    expect(c.status('orders.place'), const WordReady());
    p.dispose();
    for (final w in ['orders.place', 'orders.last', 'orders.placed']) {
      expect(c.status(w), const WordMissing(), reason: w);
    }
    expect(r.hasKind('order'), isFalse);
    expect(() => p.state(OrderState.last).define(), throwsA(isA<StateError>()));
  });

  test('tells of entities only of a kind it registered', () {
    final p = r.participant(orders, vocabularies: [WordSet.open('orders')]);
    p.registerKind(EntityKind('order', list: () => const []));
    p.entitiesChanged('order');
    expect(() => p.entitiesChanged('scene'), throwsA(isA<StateError>()));
  });

  test('a vocabulary granted is its namespace, said once where its words '
      'are', () {
    const ordersWords = WordSet('orders', [...OrderState.values]);
    final p = r.participant(orders, vocabularies: [ordersWords]);
    expect(p.namespaces, {'orders'});
    p.state(OrderState.last).define();
    expect(
      () => r.participant(cart, vocabularies: [ordersWords]),
      throwsA(isA<NotPermitted>()),
      reason: 'a namespace is one participant\'s',
    );
    expect(
      () => r.participant(
        cart,
        vocabularies: [
          const WordSet('cart', [...OrderState.values]),
        ],
      ),
      throwsArgumentError,
      reason: 'a word of the vocabulary lies outside its namespace',
    );
  });

  test('a selector is a path: every level after / is a level, and the '
      'nearest one said decides', () {
    final viewer = Principal.parse('viewer/twitch/123');
    expect(viewer.kind, 'viewer');
    expect(viewer.parent!.selector, 'viewer/twitch');
    const rules = Callers({
      'viewer': Access.deny,
      'viewer/twitch': Access.allow,
      'viewer/twitch/42': Access.deny,
    });
    expect(rules.accessOf(viewer), Access.allow);
    expect(rules.accessOf(Principal.parse('viewer/twitch/42')), Access.deny);
    expect(rules.accessOf(Principal.parse('viewer/youtube/9')), Access.deny);
  });

  test('a selector that names no one is refused, not left to match nobody', () {
    expect(
      () => StateDescriptor(
        'orders.x',
        type: const BoolType(),
        readers: Callers.only(['module:orders']),
      ),
      throwsArgumentError,
    );
    expect(
      () => r.participant(const Principal('viewer', 'twitch:1')),
      throwsArgumentError,
      reason: 'a : in an id would be a level that is not one',
    );
    expect(() => Principal.parse('module/orders/'), throwsArgumentError);
  });
}

enum _Other<T> implements IStateWord<T> {
  flag<bool>('cart.flag');

  const _Other(this.name);
  @override
  final String name;
  @override
  Shape<T> get shape => const Plain(BoolType()) as Shape<T>;
  @override
  String? get key => null;
}
