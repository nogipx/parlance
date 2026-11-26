import 'dart:io';

import 'package:test/test.dart';

/// The tools work on a participant, here or across a connection, so they
/// know no transport. Only the collector and its host adapter own RPC peers.
void main() {
  test('RPC imports stay within the collector and its host adapter', () {
    for (final e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      if (const {
        'lib/collector_host.dart',
        'lib/src/collector.dart',
        'lib/src/log_tools.dart',
        'lib/src/log_ingress.dart',
        'lib/src/host_logs.dart',
        'lib/src/journal_feed.dart',
      }.contains(e.path)) {
        continue;
      }
      final imports = RegExp(
        r'''^import '([^']+)';''',
        multiLine: true,
      ).allMatches(e.readAsStringSync()).map((m) => m[1]!);
      for (final i in imports) {
        expect(i, isNot(startsWith('package:rpc_dart')), reason: e.path);
      }
    }
  });
}
