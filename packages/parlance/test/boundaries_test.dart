import 'dart:io';

import 'package:test/test.dart';

/// The package's boundaries (skills/parlance/SKILL.md, rules of the package): imports go one way and no domain
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

  test('core imports nothing but dart:', () {
    for (final f in dartIn('lib/src/core')) {
      for (final i in importsOf(f)) {
        expect(i, startsWith('dart:'), reason: f.path);
      }
    }
  });

  test('the registry is built on core', () {
    expect(
      importsOf(File('lib/src/registry/registry.dart')),
      contains('../core/core.dart'),
    );
  });

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

  test('view uses the registry and remote, and Dart', () {
    for (final f in dartIn('lib/src/view')) {
      for (final i in importsOf(f)) {
        expect(
          i.startsWith('../registry/') ||
              i.startsWith('../remote/') ||
              i.startsWith('dart:') ||
              !i.contains('/'),
          isTrue,
          reason: '${f.path}: $i',
        );
      }
    }
  });

  test('the schema uses the registry\'s words only', () {
    for (final f in dartIn('lib/src/schema')) {
      for (final i in importsOf(f)) {
        expect(i.startsWith('../registry/'), isTrue, reason: '${f.path}: $i');
      }
    }
  });

  test('participants use the registry and the view of it, never remote', () {
    for (final f in dartIn('lib/src/participant')) {
      for (final i in importsOf(f)) {
        expect(
          i.startsWith('../registry/') ||
              i == '../view/view.dart' ||
              i.startsWith('package:clock/') ||
              i.startsWith('dart:') ||
              !i.contains('/'),
          isTrue,
          reason: '${f.path}: $i',
        );
      }
    }
  });

  test(
    'the view of a registry does not import remote; the mirror view does',
    () {
      for (final i in importsOf(File('lib/src/view/view.dart'))) {
        expect(i, isNot(contains('remote')));
      }
    },
  );

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
