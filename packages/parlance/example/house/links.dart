/// The house's links, built from its words: data for the links engine,
/// with the names and the params' types the words give.
library;

import 'package:parlance/links.dart';

import 'words.dart';

final houseLinks = <Map<String, Object?>>[
  // A reaction: a sensor sees someone, the room's light comes on.
  {
    'id': 'motion-light',
    'name': 'Light where someone moves',
    'when': [HouseFact.motion.trigger()],
    'only': [HouseState.mode.holds(Mode.home)],
    'do': [
      // A reference to the trigger's payload: still a room's id, as text.
      HouseCommand.setLight.step((room: r'$trigger.room', on: true)),
    ],
  },

  // A reaction with a temporary step: someone rings while nobody is home,
  // the porch light comes on for a while and goes off by itself.
  {
    'id': 'porch-greeting',
    'name': 'The porch lit for a visitor',
    'when': [HouseFact.rang.trigger()],
    'only': [HouseState.mode.holds(Mode.away)],
    'do': [
      {
        'temporarily': {
          'for': '300ms',
          'do': [HouseCommand.setLight.step((room: 'porch', on: true))],
        },
      },
    ],
  },

  // A binding: while it is night, the heating is held at 17 °C; when the
  // night ends, it goes back to what it was.
  {
    'id': 'night-heat',
    'name': 'Cooler at night',
    'while': [HouseState.mode.holds(Mode.night)],
    'hold': [HouseCommand.setHeat.step((target: 17))],
  },

  // A constraint: nobody unlocks the door while the house is away.
  {
    'id': 'away-door',
    'name': 'Locked while away',
    'deny': {
      'command': HouseCommand.lock.name,
      'where': {'on': false},
    },
    'while': [HouseState.mode.holds(Mode.away)],
    'reason': 'nobody is home',
    // Unlike the house's night guard, no one overrides it.
    'overridable': false,
  },

  // An own command: `my.movie`, the lights down in one go.
  {
    'id': 'movie',
    'command': 'movie',
    'do': [
      HouseCommand.setLight.step((room: 'living', on: false)),
      HouseCommand.setLight.step((room: 'kitchen', on: false)),
    ],
  },

  // An own state: `my.guests`, a flag the residents set.
  {'id': 'guests', 'state': 'guests', 'default': false},
];
