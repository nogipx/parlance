import 'package:parlance/tools.dart';
import 'package:test/test.dart';
import 'package:parlance/src/registry/registry.dart' show RawRegistry;
import 'package:parlance/src/participant/local.dart' show Participants;

const owner = Principal('host');

/// As json_serializable makes one: fromJson, toJson.
final class Address {
  const Address(this.city);
  factory Address.fromJson(Map<String, Object?> m) =>
      Address(m['city']! as String);
  final String city;
  Map<String, Object?> toJson() => {'city': city};
}

final class Order {
  const Order(this.id, this.to, {this.explicit = true});
  factory Order.fromJson(Map<String, Object?> m) =>
      Order(m['id']! as String, Address.fromJson((m['to']! as Map).cast()));
  final String id;
  final Address to;

  /// Whether toJson goes all the way down (`explicitToJson: true`).
  final bool explicit;
  Map<String, Object?> toJson() => {
    'id': id,
    'to': explicit ? to.toJson() : to,
  };

  @override
  bool operator ==(Object other) =>
      other is Order && other.id == id && other.to.city == to.city;

  @override
  int get hashCode => Object.hash(id, to.city);
}

const _orderType = RecordType({
  'id': Field(TextType()),
  'to': Field(RecordType({'city': Field(TextType())})),
});

enum Orders<T> implements IStateWord<T> {
  last<Order>(
    'orders.last',
    JsonShape(from: Order.fromJson, to: _toJson, type: _orderType),
  ),
  loose<Order>('orders.loose', JsonShape(from: Order.fromJson, to: _toJson));

  const Orders(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  String? get key => null;
}

Map<String, Object?> _toJson(Order o) => o.toJson();

void main() {
  late Registry r;
  late GeneratedWords orders;
  setUp(() {
    r = Registry();
    orders = GeneratedWords(
      r.participant(owner, vocabularies: [WordSet.open('orders')]),
    );
  });
  tearDown(() => r.dispose());

  test('a class that serializes itself is a state as it is', () {
    final last = orders.state(Orders.last).define();
    last.set(const Order('o1', Address('Riga')));
    expect(
      orders.stateOf(Orders.last).value,
      const Order('o1', Address('Riga')),
    );
    expect(r.read('orders.last'), {
      'id': 'o1',
      'to': {'city': 'Riga'},
    });
    expect(
      r.stateDescriptor('orders.last')!.type.toJson(),
      _orderType.toJson(),
    );
  });

  test('its toJson must give JSON all the way down', () {
    final last = orders.state(Orders.last).define();
    expect(
      () => last.set(const Order('o2', Address('Oslo'), explicit: false)),
      throwsA(
        isA<ArgumentError>().having(
          (e) => '${e.message}',
          'message',
          contains('explicitToJson'),
        ),
      ),
    );
  });

  test('without a type any object passes, and lists of them work', () {
    orders.state(Orders.loose).define().set(const Order('o3', Address('Pori')));
    expect(orders.stateOf(Orders.loose).value!.to.city, 'Pori');
    const list = ListShape(JsonShape(from: Order.fromJson, to: _toJson));
    final json = list.toJson(const [Order('a', Address('x'))]);
    expect(list.fromJson(json), const [Order('a', Address('x'))]);
  });
}
