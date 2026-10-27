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
  IHandle define({Callers callers = const Callers({'*': Access.allow})}) =>
      r.defineCommand(
        CommandDescriptor(
          'orders.page',
          params: const ObjectType({'from': Field(IntType())}),
          returns: const ListType(TextType()),
          callers: callers,
          query: true,
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

  test('who may ask is its callers', () async {
    define(callers: Callers.only(['module:orders']));
    final r1 = await r.call('orders.page', {'from': 0}, by: asker);
    expect((r1 as CallRefused).code, Refusal.notPermitted);
    expect(asked, 0);
  });

  test('a query sets nothing and no hook runs ahead of it', () {
    expect(
      () => CommandDescriptor(
        'orders.x',
        params: const ObjectType({'on': Field(BoolType())}),
        callers: const Callers({'*': Access.allow}),
        sets: const Sets('orders.on', value: 'on'),
        query: true,
      ),
      throwsArgumentError,
    );
    expect(
      () => CommandDescriptor(
        'orders.x',
        callers: const Callers({'*': Access.allow}),
        interceptable: true,
        query: true,
      ),
      throwsArgumentError,
    );
  });

  test('it says it is a query in the catalog', () {
    define();
    final d = r.commandDescriptor('orders.page')!;
    expect(d.toJson()['query'], isTrue);
    expect(CommandDescriptor.fromJson(d.toJson()).query, isTrue);
  });

  test('through a participant: typed, and asked by whoever may read', () async {
    final p = r.participant(
      owner,
      namespaces: {'orders'},
      access: WordAccess(read: Callers.only(['module'])),
    );
    p.query(OrdersQuery.page).define((c) => ['o${c.params.from}']);
    expect(r.commandDescriptor('orders.page')!.callers.rules.keys, {'module'});
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
      open.commandDescriptor('orders.page')!.callers.allows(asker),
      isTrue,
      reason: 'no default: everyone may ask, as everyone may read',
    );
  });

  test(
    'typed on the registry: asked by everyone unless its askers say',
    () async {
      r.query(OrdersQuery.page).define((c) => ['p${c.params.from}']);
      expect(r.commandDescriptor('orders.page')!.query, isTrue);
      final a = await r.query(OrdersQuery.page).ask((from: 1), by: asker);
      expect((a as CallDone<List<String>>).value, ['p1']);
      final viaView = await LocalView(
        r,
        by: asker,
      ).query(OrdersQuery.page).ask((from: 2));
      expect((viaView as CallDone<List<String>>).value, ['p2']);
    },
  );
}
