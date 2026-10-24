import 'dart:io';

import 'package:test/test.dart';

/// The package's boundaries (skills/switchboard/SKILL.md, rules of the package): imports go one way and no domain
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

  test('mcp imports neither links nor rpc_dart, only their words', () {
    for (final f in dartIn('lib/src/mcp')) {
      for (final i in importsOf(f)) {
        if (i == '../link_words.dart') continue;
        expect(i, isNot(contains('link')), reason: f.path);
        expect(i, isNot(startsWith('package:rpc_dart')), reason: f.path);
      }
    }
  });

  test('the words of links import only the registry\'s types and words', () {
    expect(importsOf(File('lib/src/link_words.dart')), {
      'registry/types.dart',
      'registry/words.dart',
    });
  });

  test('owners use the registry alone', () {
    for (final f in dartIn('lib/src/owners')) {
      for (final i in importsOf(f)) {
        expect(i, startsWith('../registry/'), reason: f.path);
      }
    }
  });

  test('the registry names nothing of links', () {
    for (final f in dartIn('lib/src/registry')) {
      expect(
        RegExp(r"'links?[.']").firstMatch(f.readAsStringSync())?[0],
        isNull,
        reason: f.path,
      );
    }
  });

  test('mcp and remote name no link word but through LinkWords', () {
    for (final f in [...dartIn('lib/src/mcp'), ...dartIn('lib/src/remote')]) {
      expect(
        RegExp(r"'links\.\w").firstMatch(f.readAsStringSync())?[0],
        isNull,
        reason: f.path,
      );
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
