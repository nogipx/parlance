import 'dart:async';

import 'package:parlance/tools.dart';
import 'package:test/test.dart';
import 'package:parlance/src/registry/registry.dart' show RawRegistry;

const orders = Principal('module', 'orders');
const cart = Principal('module', 'cart');
const someone = Principal('visitor', 'v1');

typedef Order = ({String id, String status});

final _order = RecordShape<Order>(
  {'id': Part(PlainShape(TextType())), 'status': Part(PlainShape(TextType()))},
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
  Shape<R>? get returns => const PlainShape(TextType()) as Shape<R>;
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
      last.set(c.params);
      placed.say(c.params);
      return c.params.id;
    }, callers: Callers.only(['module/cart']));
    return p;
  }

  group('a participant defines', () {
    test(
      'words in its vocabularies, used by others through typed words',
      () async {
        ordersModule();
        final c = r.participant(cart, vocabularies: [WordSet.open('cart')]);
        final heard = <Order>[];
        final sub = c
            .fact(OrderFact.placed)
            .facts
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

    test('nothing outside its vocabularies', () {
      final p = r.participant(orders, vocabularies: [WordSet.open('orders')]);
      expect(() => p.state(_Other.flag).define(), throwsA(isA<StateError>()));
      expect(r.stateDescriptor('cart.flag'), isNull);
      final none = r.participant(const Principal('module', 'x'));
      expect(
        () => none.state(OrderState.last).define(),
        throwsA(isA<StateError>()),
        reason: 'no vocabulary, no words',
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

  group('vocabularies', () {
    test('are one participant\'s, until it goes', () {
      final a = r.participant(orders, vocabularies: [WordSet.open('orders')]);
      expect(
        () => r.participant(cart, vocabularies: [WordSet.open('orders')]),
        throwsA(isA<StateError>()),
      );
      a.dispose();
      expect(
        r
            .participant(cart, vocabularies: [WordSet.open('orders')])
            .vocabularyNames,
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
        () => (flag as StateWriterOf<bool>).set(
          true,
          cause: const Cause(someone),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('speaks for another only when its rights let it', () async {
      final lock = r.participant(
        orders,
        vocabularies: [WordSet.open('orders')],
      );
      final a = lock.fact(OrderFact.placed).define();
      expect(
        () => (a as FactEmitterOf<Order>).emit((
          id: 'o',
          status: 'new',
        ), cause: const Cause(someone)),
        throwsA(isA<StateError>()),
      );
      lock.dispose();
      final voice = r.participant(
        orders,
        vocabularies: [WordSet.open('orders')],
        rights: ParticipantRights(
          speakFor: (_, by, _) => by.kind == 'visitor' ? null : 'visitors only',
        ),
      );
      (voice.fact(OrderFact.placed).define() as FactEmitterOf<Order>).emit((
        id: 'o',
        status: 'new',
      ), cause: const Cause(someone));
      expect(r.recent('orders.placed').single.cause.by, someone);
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
          readers: Callers.only(['module/orders', 'module/cart']),
          callers: Callers.only(['module/cart']),
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
    test('a selector names the owners of what it names; the nearest wins; '
        'an owner has none', () {
      final sync = orders.child('sync');
      expect(sync, const Principal('module', 'orders', 'sync'));
      expect(sync.selector, 'module/orders@sync');
      expect(Principal.parse('module/orders@sync'), sync);
      expect(Principal.fromJson(sync.toJson()), sync);
      expect(const Principal('house').child('screen').selector, 'house@screen');
      expect(() => sync.child('push'), throwsStateError);
      expect(sync.isWithin(orders), isTrue);
      expect(sync.isWithin(const Principal('module')), isTrue);
      expect(orders.isWithin(sync), isFalse);
      expect(orders.child('ui').isWithin(sync), isFalse);
      expect(sync.parent, orders);
      final callers = Callers({
        'module/orders': Access.allow,
        'module/orders@sync': Access.deny,
      });
      expect(callers.allows(orders.child('ui')), isTrue, reason: 'its whole');
      expect(callers.allows(sync), isFalse, reason: 'its own rule');
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
      (flag as StateWriterOf<bool>).set(false, cause: const Cause(cart));
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
        CommandDescriptor('orders.a', callers: Callers.anyone),
        (_) {},
      );
      b.defineCommand(
        CommandDescriptor('orders.b', callers: Callers.anyone),
        (_) {},
      );
      a.addGuard('orders.no', (_) => 'no');
      expect((await r.call('orders.a', {}, by: cart)).ok, isFalse);
      expect((await r.call('orders.b', {}, by: cart)).ok, isTrue);
    });

    test('a whole\'s guard judges the commands of all its parts', () async {
      final p = r.participant(orders, vocabularies: [WordSet.open('orders')]);
      p
          .child('a')
          .defineCommand(
            CommandDescriptor('orders.a', callers: Callers.anyone),
            (_) {},
          );
      p.addGuard('orders.no', (_) => 'no');
      final refused = await r.call('orders.a', {}, by: cart);
      expect((refused as CallRefused).guard, '${orders.selector}#orders.no');
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
        params: RecordType({'id': Field(TextType())}),
        callers: Callers.anyone,
      ),
      (_) => flagged++,
    );
    final denied = await c.call('orders.place', {'id': 'o3', 'status': 'new'});
    expect((denied as CallRefused).code, Refusal.denied);
    expect((await c.call('cart.add', {'id': 'o3'})).ok, isTrue);
    expect(flagged, 1, reason: 'the guard does not judge another\'s command');
  });

  test('a guard is known by its participant and its id', () async {
    final p = ordersModule();
    p.addGuard('no', (_) => 'no');
    final c = r.participant(cart, vocabularies: [WordSet.open('cart')]);
    expect(() => c.addGuard('no', (_) => null), returnsNormally);
    final denied = await c.call('orders.place', {'id': 'o1', 'status': 'new'});
    expect((denied as CallRefused).guard, '${orders.selector}#no');
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
    expect(() => p.entitiesChanged('room'), throwsA(isA<StateError>()));
  });

  test(
    'two vocabularies of one name, or one inside the other, are refused',
    () {
      expect(
        () => r.participant(
          orders,
          vocabularies: [WordSet.open('orders'), WordSet.open('orders')],
        ),
        throwsArgumentError,
      );
      expect(
        () => r.participant(
          orders,
          vocabularies: [WordSet.open('orders.archive')],
        ),
        throwsArgumentError,
        reason: 'a vocabulary is one word',
      );
      expect(
        r
            .participant(
              orders,
              vocabularies: [WordSet.open('orders'), WordSet.open('cart')],
            )
            .vocabularyNames,
        {'orders', 'cart'},
      );
    },
  );

  test('a vocabulary granted is named once, where its words '
      'are', () {
    const ordersWords = WordSet('orders', [...OrderState.values]);
    final p = r.participant(orders, vocabularies: [ordersWords]);
    expect(p.vocabularyNames, {'orders'});
    p.state(OrderState.last).define();
    expect(
      () => r.participant(cart, vocabularies: [ordersWords]),
      throwsA(isA<NotPermitted>()),
      reason: 'a vocabulary is one participant\'s',
    );
    expect(
      () => r.participant(
        cart,
        vocabularies: [
          const WordSet('cart', [...OrderState.values]),
        ],
      ),
      throwsArgumentError,
      reason: 'a word of the vocabulary is not named in it',
    );
    expect(
      () => r.participant(
        cart,
        vocabularies: [
          const WordSet('cart', [_Spaced.word]),
        ],
      ),
      throwsA(
        isA<ArgumentError>().having(
          (e) => '${e.message}',
          'message',
          allOf(contains('"cart.locked talk"'), contains('joined by _ or -')),
        ),
      ),
      reason: 'every name is checked when the vocabulary is granted',
    );
  });

  test('a selector is kind[/id][@owner], and the nearest one said '
      'decides', () {
    final visitor = Principal.parse('visitor/gate.123');
    expect(
      (visitor.kind, visitor.id, visitor.owner),
      ('visitor', 'gate.123', ''),
    );
    expect(visitor.parent!.selector, 'visitor');
    const rules = Callers({
      'visitor': Access.allow,
      'visitor/gate.42': Access.deny,
    });
    expect(rules.accessOf(visitor), Access.allow);
    expect(rules.accessOf(Principal.parse('visitor/gate.42')), Access.deny);
    expect(rules.accessOf(Principal.parse('member/9')), Access.deny);
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
      () => r.participant(const Principal('visitor', 'gate:1')),
      throwsArgumentError,
      reason: 'a : in an id would be a level that is not one',
    );
    expect(() => Principal.parse('module/orders/'), throwsArgumentError);
    expect(() => Principal.parse('module/'), throwsArgumentError);
    expect(() => Principal.parse('module/orders@'), throwsArgumentError);
    expect(() => Principal.parse('visitor/gate/1'), throwsArgumentError);
    expect(() => Principal.parse('house@a@b'), throwsArgumentError);
    expect(() => Principal.parse('house@Screen'), throwsArgumentError);
    for (final reserved in ['#', '/', ':', '*', ' ', '~', '%']) {
      expect(
        () => Principal.parse('visitor/bo${reserved}1'),
        throwsArgumentError,
        reason: '$reserved is reserved',
      );
    }
    expect(() => Principal.parse('Visitor/x'), throwsArgumentError);
    expect(Principal.parse('visitor/UC_a-b.c').id, 'UC_a-b.c');
  });

  test('a text from outside becomes a level: as it is when it is one, else '
      'its other signs as _ and a hash of it, never two as one', () {
    expect(Principal.idOf('cool_guy_99'), 'cool_guy_99');
    expect(Principal.idOf('UCabc-D_e.f'), 'UCabc-D_e.f');
    expect(Principal.idOf('ann@mail.com'), 'ann_mail.com.1278c97d19647cda');
    expect(
      Principal.idOf('ann#mail.com'),
      isNot(Principal.idOf('ann@mail.com')),
    );
    expect(Principal.idOf('a'), 'a');
    expect(Principal.idOf('Вася'), matches(RegExp(r'^x_\.[0-9a-f]{16}$')));
    expect(Principal.idOf(''), matches(RegExp(r'^x\.[0-9a-f]{16}$')));
    // A name taken as another's made id is not given that id.
    final made = Principal.idOf('ann@mail.com');
    expect(Principal.idOf(made), isNot(made));
    expect(Principal.idOf(made), startsWith('$made.'));
    for (final t in ['ann@mail.com', 'Вася', '', ' b ']) {
      expect(
        () => Principal('visitor', Principal.idOf(t)).check(),
        returnsNormally,
      );
    }
  });
}

enum _Other<T> implements IStateWord<T> {
  flag<bool>('cart.flag');

  const _Other(this.name);
  @override
  final String name;
  @override
  Shape<T> get shape => const PlainShape(BoolType()) as Shape<T>;
  @override
  String? get key => null;
}

enum _Spaced<T> implements IStateWord<T> {
  word<bool>('cart.locked talk');

  const _Spaced(this.name);
  @override
  final String name;
  @override
  Shape<T> get shape => const PlainShape(BoolType()) as Shape<T>;
  @override
  String? get key => null;
}
