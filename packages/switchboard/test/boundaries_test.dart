import 'dart:io';

import 'package:test/test.dart';

/// The package's boundaries (SPEC, top): imports go one way and no domain
/// word is in it.
void main() {
  List<File> dartIn(String dir) => [
    for (final e in Directory(dir).listSync(recursive: true))
      if (e is File && e.path.endsWith('.dart')) e,
  ];

  Iterable<String> importsOf(File f) => RegExp(
    r'''^import '([^']+)';''',
    multiLine: true,
  ).allMatches(f.readAsStringSync()).map((m) => m[1]!);

  test('registry imports neither links nor remote', () {
    for (final f in dartIn('lib/src/registry')) {
      for (final i in importsOf(f)) {
        expect(i, isNot(contains('links')), reason: f.path);
        expect(i, isNot(contains('remote')), reason: f.path);
        expect(i, isNot(startsWith('package:rpc_dart')), reason: f.path);
      }
    }
  });

  test('links imports the registry only, never remote or rpc_dart', () {
    for (final f in dartIn('lib/src/links')) {
      for (final i in importsOf(f)) {
        expect(i, isNot(contains('remote')), reason: f.path);
        expect(i, isNot(startsWith('package:rpc_dart')), reason: f.path);
      }
    }
  });

  test('remote does not import links', () {
    for (final f in dartIn('lib/src/remote')) {
      for (final i in importsOf(f)) {
        expect(i, isNot(contains('links')), reason: f.path);
      }
    }
  });

  test('no word of the domain the package was made for', () {
    final words = RegExp(
      r'\b(tephra|scene|viewer|twitch|chat|streamer|obs|raid|donation|overlay)s?\b',
      caseSensitive: false,
    );
    for (final f in dartIn('lib')) {
      final hit = words.firstMatch(f.readAsStringSync());
      expect(hit?[0], isNull, reason: f.path);
    }
  });
}
