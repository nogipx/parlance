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

  test('registry does not import remote; of rpc_dart, only its logger', () {
    for (final f in dartIn('lib/src/registry')) {
      for (final i in importsOf(f)) {
        expect(i, isNot(contains('remote')), reason: f.path);
        if (i.startsWith('package:rpc_dart')) {
          expect(i, 'package:rpc_dart/logger.dart', reason: f.path);
        }
      }
    }
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
