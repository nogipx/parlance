import 'package:switchboard/links.dart';
import 'package:switchboard/registry.dart';
import 'package:test/test.dart';

/// A host that is not a streaming studio: a house with rooms and lights,
/// residents and guests, a doorbell. If it lives on the package without a
/// change to it, the package has no streaming in it (SPEC §§1, 13).
void main() {
  const resident = Principal('resident', 'ann');
  const guest = Principal('guest', 'bob');
  const house = Principal('device', 'hub');

  late Registry r;
  late Links links;
  late RawStateWriter lights;
  late RawStateWriter occupied;
  late RawFactEmitter bell;
  final rooms = ['hall', 'kitchen'];

  setUp(() {
    r = Registry(overriders: {'resident'});
    r.registerKind(
      EntityKind('room', list: () => [for (final x in rooms) EntityRef(x)]),
    );
    lights = r.defineState(
      StateDescriptor('home.light', type: const BoolType(), key: 'room'),
      by: house,
    );
    occupied = r.defineState(
      StateDescriptor('home.occupied', type: const BoolType(), key: 'room'),
      by: house,
    );
    r.defineCommand(
      CommandDescriptor(
        'home.light.set',
        params: const ObjectType({
          'room': Field(RefType('room')),
          'on': Field(BoolType()),
        }),
        callers: const Callers({
          'resident': Access.allow,
          'guest': Access.warn,
          'link': Access.allow,
          'system': Access.allow,
        }),
        sets: const Sets('home.light', key: 'room', value: 'on'),
      ),
      (c) => lights.set(c.params['on'], key: c.params['room'] as String),
    );
    bell = r.defineFact(
      FactDescriptor('home.doorbell', type: const AnyType()),
      by: house,
    );
    links = Links(r);
    links.registerAnchor(
      AnchorKind(
        'room',
        entityKind: 'room',
        condition: (id) =>
            StateIs('home.occupied', id, const ValueTest(Op.isEqual, true)),
      ),
    );
    for (final room in rooms) {
      lights.set(false, key: room);
      occupied.set(false, key: room);
    }
  });

  test(
    'while a room is occupied its light is on; a resident overrides',
    () async {
      final problems = links.apply([
        {
          'id': 'kitchen-light',
          'anchor': {'room': 'kitchen'},
          'hold': [
            {
              'call': 'home.light.set',
              'params': {'room': 'kitchen', 'on': true},
            },
          ],
        },
      ]);
      expect(problems, isEmpty);
      occupied.set(true, key: 'kitchen');
      await pumpEventQueue();
      expect(r.read('home.light', key: 'kitchen'), true);
      await r.call('home.light.set', {
        'room': 'kitchen',
        'on': false,
      }, by: resident);
      occupied.set(false, key: 'kitchen');
      await pumpEventQueue();
      expect(r.read('home.light', key: 'kitchen'), false);
    },
  );

  test(
    'night mode: guests may not touch the lights; the bell lights the hall for a while',
    () async {
      links.apply([
        {'id': 'night', 'state': 'night'},
        {
          'id': 'no-guests',
          'deny': {'namespace': 'home'},
          'callers': ['guest'],
          'while': [
            {'state': 'my.night', 'is': true},
          ],
          'reason': 'night',
        },
        {
          'id': 'bell',
          'when': [
            {'fact': 'home.doorbell'},
          ],
          'only': [
            {'state': 'my.night', 'is': true},
          ],
          'do': [
            {
              'temporarily': {
                'for': '2m',
                'do': [
                  {
                    'call': 'home.light.set',
                    'params': {'room': 'hall', 'on': true},
                  },
                ],
              },
            },
          ],
        },
      ]);
      expect(
        (await r.call('home.light.set', {
          'room': 'hall',
          'on': true,
        }, by: guest)).ok,
        isTrue,
      );
      await r.call('home.light.set', {
        'room': 'hall',
        'on': false,
      }, by: resident);
      await r.call('my.night.set', {'value': true}, by: resident);
      expect(
        (await r.call('home.light.set', {
          'room': 'hall',
          'on': true,
        }, by: guest)).ok,
        isFalse,
      );
      bell.emit(null);
      await pumpEventQueue();
      expect(r.read('home.light', key: 'hall'), true);
    },
  );
}
