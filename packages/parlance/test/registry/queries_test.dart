import 'dart:async';

import 'package:parlance/participant.dart';
import 'package:parlance/registry.dart';
import 'package:parlance/view.dart';
import 'package:test/test.dart';

const owner = Principal('module', 'orders');
const asker = Principal('module', 'cart');

typedef Page = ({int from});

final _page = RecordShape<Page>(
  {'from': Part(Plain(IntType()))},
  to: (p) => {'from': p.from},
  from: (m) => (from: m['from']! as int),
);

enum OrdersQuery<P, R> implements IQueryWord<P, R> {
  page<Page, List<String>>('orders.page');

  const OrdersQuery(this.name);
  @override
  final String name;
  @override
  RecordShape<P> get params => _page as RecordShape<P>;
  @override
  Shape<R> get returns => const ListShape(Plain(TextType())) as Shape<R>;
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late Registry r;
  setUp(() => r = Registry());
  tearDown(() => r.dispose());

  var asked = 0;
  IHandle define({Callers askers = const Callers({'*': Access.allow})}) =>
      r.defineQuery(
        QueryDescriptor(
          'orders.page',
          params: const ObjectType({'from': Field(IntType())}),
          returns: const ListType(TextType()),
          askers: askers,
        ),
        (c) {
          asked++;
          final from = c.params['from']! as int;
          return [for (var i = from; i < from + 2; i++) 'o$i'];
        },
      );

  setUp(() => asked = 0);

  test('a query answers, and asking again asks again', () async {
    define();
    final records = <CallRecord>[];
    final sub = r.calls.listen(records.add);
    final a = await r.call('orders.page', {'from': 0}, by: asker, id: 'q');
    final b = await r.call('orders.page', {'from': 5}, by: asker, id: 'q');
    await settle();
    expect((a as CallDone).value, ['o0', 'o1']);
    expect((b as CallDone).value, ['o5', 'o6'], reason: 'no id held to it');
    expect(asked, 2);
    expect(records, isEmpty, reason: 'no call record keeps an answer');
    await sub.cancel();
  });

  test('who may ask is its askers', () async {
    define(askers: Callers.only(['module:orders']));
    final r1 = await r.call('orders.page', {'from': 0}, by: asker);
    expect((r1 as CallRefused).code, Refusal.notPermitted);
    expect(asked, 0);
  });

  test('it is a word of its own kind in the catalog, not a command', () {
    define();
    expect(r.commandDescriptor('orders.page'), isNull);
    final d = r.queryDescriptor('orders.page')!;
    expect(d.toJson()['is'], 'query');
    expect(d.toJson().containsKey('sets'), isFalse);
    final back = Descriptor.fromJson(d.toJson());
    expect(back, isA<QueryDescriptor>());
    expect((back as QueryDescriptor).askers.toJson(), d.askers.toJson());
    expect(r.catalog.whereType<QueryDescriptor>().single.name, 'orders.page');
  });

  test('a hook cannot run ahead of it, as it says it takes none', () {
    define();
    expect(
      () => r.addBefore(
        'orders.page',
        'h',
        (_, _) async {},
        timeout: const Duration(seconds: 1),
      ),
      throwsStateError,
    );
  });

  test('through a participant: typed, and asked by whoever may read', () async {
    final p = r.participant(
      owner,
      namespaces: {'orders'},
      access: WordAccess(read: Callers.only(['module'])),
    );
    p.query(OrdersQuery.page).define((c) => ['o${c.params.from}']);
    expect(r.queryDescriptor('orders.page')!.askers.rules.keys, {'module'});
    final answer = await r.participant(asker).query(OrdersQuery.page).ask((
      from: 3,
    ));
    expect((answer as CallDone<List<String>>).value, ['o3']);

    final open = Registry();
    addTearDown(open.dispose);
    open
        .participant(owner, namespaces: {'orders'})
        .query(OrdersQuery.page)
        .define((c) => const []);
    expect(
      open.queryDescriptor('orders.page')!.askers.allows(asker),
      isTrue,
      reason: 'no default: everyone may ask, as everyone may read',
    );
  });

  test(
    'typed on the registry: asked by everyone unless its askers say',
    () async {
      r.query(OrdersQuery.page).define((c) => ['p${c.params.from}']);
      expect(r.queryDescriptor('orders.page'), isNotNull);
      final a = await r.query(OrdersQuery.page).ask((from: 1), by: asker);
      expect((a as CallDone<List<String>>).value, ['p1']);
      final viaView = await LocalView(
        r,
        by: asker,
      ).query(OrdersQuery.page).ask((from: 2));
      expect((viaView as CallDone<List<String>>).value, ['p2']);
    },
  );

  group('a query changes nothing', () {
    late StateWriterOf<String> note;
    late FactEmitterOf<String> said;
    setUp(() {
      note = r.state(_Note.text).define(by: owner)..set('before');
      said = r.fact(_Said.it).define(by: owner);
      r.defineCommand(
        CommandDescriptor(
          'orders.touch',
          callers: const Callers({'*': Access.allow}),
        ),
        (_) {},
      );
    });

    /// Asks a query whose handler does [effect]; the query goes after.
    Future<CallResult<List<String>>> askWith(
      FutureOr<void> Function() effect,
    ) async {
      final h = r.query(OrdersQuery.page).define((q) async {
        await effect();
        return const [];
      });
      try {
        return await r.query(OrdersQuery.page).ask((from: 0), by: asker);
      } finally {
        h.dispose();
      }
    }

    test(
      'a write from its handler is refused, and nothing is written',
      () async {
        final out = await askWith(() => note.set('after'));
        expect(out, isA<CallFailed>());
        expect(out.whyNot, contains('orders.page is a query'));
        expect(out.whyNot, contains('write orders.note'));
        expect(r.read('orders.note'), 'before');
      },
    );

    test('so is one made later, after an await or in a timer', () async {
      final out = await askWith(() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        note.set('later');
      });
      expect(out, isA<CallFailed>());
      expect(r.read('orders.note'), 'before');
    });

    test(
      'a fact or a command from it is refused; another query it may ask',
      () async {
        expect(await askWith(() => said.emit('hi')), isA<CallFailed>());
        expect(r.recent('orders.said'), isEmpty);
        r.dispose();
        r = Registry();
        r.defineCommand(
          CommandDescriptor(
            'orders.touch',
            callers: const Callers({'*': Access.allow}),
          ),
          (_) {},
        );
        r.defineQuery(
          QueryDescriptor(
            'orders.count',
            returns: const IntType(),
            askers: const Callers({'*': Access.allow}),
          ),
          (_) => 3,
        );
        final calling = await askWith(
          () => r.call('orders.touch', {}, by: owner),
        );
        expect(calling.whyNot, contains('call orders.touch'));
        r.query(OrdersQuery.page).define((q) async {
          final n = await r.call(
            'orders.count',
            {},
            by: owner,
            cause: q.askingFor(owner),
          );
          return ['${(n as CallDone).value}'];
        });
        final nested = await r.query(OrdersQuery.page).ask((
          from: 0,
        ), by: asker);
        expect((nested as CallDone<List<String>>).value, ['3']);
      },
    );

    test('outside a query the same write goes through', () {
      note.set('after');
      expect(r.read('orders.note'), 'after');
      expect(answeringQuery(), isNull);
    });
  });
}

enum _Note<T> implements IStateWord<T> {
  text<String>('orders.note');

  const _Note(this.name);
  @override
  final String name;
  @override
  Shape<T> get shape => const Plain(TextType()) as Shape<T>;
  @override
  String? get key => null;
}

enum _Said<T> implements IFactWord<T> {
  it<String>('orders.said');

  const _Said(this.name);
  @override
  final String name;
  @override
  Shape<T> get shape => const Plain(TextType()) as Shape<T>;
}
