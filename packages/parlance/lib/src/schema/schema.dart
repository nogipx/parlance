import '../registry/compat.dart';
import '../registry/words.dart';

/// What [words] say of themselves, by name: each word's kind and its types
/// (SPEC §23.3). What a release of them says is the baseline the next is
/// compared with ([schemaBreaks], [breaksSince]), so a published word does
/// not change by accident.
Map<String, Object?> schemaOf(Iterable<IWord> words) => schemasOf(words);

/// What of the words in [before] that [now] breaks for code built against
/// [before] (SPEC §25.1): a word gone (`<word> is gone`), or each place it
/// breaks (`<word>: <path>: was …, is …`), every one at once. A word added
/// is no break, nor what code built against [before] still reads and gives
/// as it did: a field added to what it reads, a param it may leave out, a
/// wider bound on what it gives. Empty when nothing published breaks;
/// otherwise a new version of the word keeps the old one (SPEC §1), or the
/// change is accepted on purpose by keeping [now] as the new baseline. The
/// same rule holds a word met at run time to the one code was built
/// against (SPEC §6.5, §6.9).
List<String> schemaBreaks(
  Map<String, Object?> before,
  Map<String, Object?> now,
) => [
  for (final MapEntry(:key, :value) in before.entries)
    if (!now.containsKey(key))
      '$key is gone'
    else
      for (final b in entryBreaks(value, now[key])) '$key: $b',
];

/// [schemaBreaks] of [now] against each of [releases], the schemas of the
/// releases still in use by name (a version), oldest first; only those it
/// breaks (SPEC §25.3). Against every one: a break accepted on purpose
/// once hides, release by release, from every later comparison, while
/// code built before it still runs. [latest]: against the newest only, for
/// words no code outlives a release of.
Map<String, List<String>> breaksSince(
  Map<String, Map<String, Object?>> releases,
  Map<String, Object?> now, {
  bool latest = false,
}) => {
  for (final MapEntry(key: version, value: schema)
      in latest ? releases.entries.skip(releases.length - 1) : releases.entries)
    if (schemaBreaks(schema, now) case final breaks when breaks.isNotEmpty)
      version: breaks,
};
