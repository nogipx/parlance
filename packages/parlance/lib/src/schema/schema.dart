import '../registry/compat.dart';
import '../registry/words.dart';

/// What [words] say of themselves, by name: each word's kind and its types
/// (SPEC §23.3). A module keeps it beside its words and compares the next
/// with it ([schemaBreaks]), so a published word does not change by
/// accident.
Map<String, Object?> schemaOf(Iterable<IWord> words) => {
  for (final w in words) w.name: schemaOfWord(w),
};

/// What changed of the words in [before] that [now] does not say the same:
/// a word gone, or its kind or types changed. A word added is no break,
/// nor a param a command or query takes now that a caller may leave out
/// (optional, or with a default): every call made before still passes.
/// Empty when nothing published changed; otherwise a new version of the
/// word keeps the old one (SPEC §1), or the change is accepted on purpose
/// by keeping [now] as the new baseline. The same rule holds a word met at
/// run time to the one code was built against (SPEC §6.5).
List<String> schemaBreaks(
  Map<String, Object?> before,
  Map<String, Object?> now,
) => [
  for (final MapEntry(:key, :value) in before.entries)
    if (!now.containsKey(key))
      '$key is gone'
    else if (!keepsPromises(value, now[key]))
      '$key changed',
];
