import 'dart:async';
import 'dart:convert';

import 'package:parlance/tools.dart';
import 'package:parlance_mcp/src/journal_feed.dart';
import 'package:test/test.dart';

void main() {
  test('journal paging reports evicted and oversized entries once', () async {
    final events = StreamController<JournalEntry>.broadcast(sync: true);
    final feed = JournalFeed(events.stream);
    addTearDown(feed.close);
    JournalDiagnostic entry(int n, String word) => JournalDiagnostic(
      id: 'e$n',
      word: word,
      cause: const Cause(Principal('test')),
      at: DateTime.utc(2026),
      event: 'word.defined',
      epoch: 'test',
      n: n,
    );
    for (var i = 1; i <= 1100; i++) {
      events.add(entry(i, 'test/test.word'));
    }
    events.add(entry(1101, 'x' * 70000));
    await events.close();
    int cursor = 0, dropped = 0;
    final numbers = <int>[];
    while (true) {
      final page = feed.page(cursor);
      for (final line in page['lines'] as List<String>) {
        numbers.add((jsonDecode(line) as Map<String, dynamic>)['n'] as int);
      }
      dropped += page['dropped'] as int;
      cursor = page['cursor'] as int;
      if (page['more'] != true) break;
    }
    expect(cursor, 1101);
    expect(dropped, 77);
    expect(numbers, orderedEquals(List.generate(1024, (i) => 77 + i)));
    expect(feed.page(cursor)['lines'], isEmpty);
    expect(feed.page(cursor)['dropped'], 0);
  });
}
