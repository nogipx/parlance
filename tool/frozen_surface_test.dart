/// Standalone regression checks for the release compatibility gate.
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';

import 'frozen_surface.dart';
import 'surface.dart';

Future<void> main() async {
  final root = Directory.systemTemp.createTempSync('parlance_frozen_surface_');
  var checked = 0;
  try {
    void release(String current, List<String> tags, String? expected) {
      checked++;
      final selected = latestCompatibleRelease(current, tags);
      if (selected != expected) {
        throw StateError(
          'release case $checked: $current selected $selected, expected $expected',
        );
      }
    }

    release('0.3.0', ['parlance-0.2.0'], null);
    release('0.3.1', ['parlance-0.2.9', 'parlance-0.3.0'], 'parlance-0.3.0');
    release('0.3.2', [
      'parlance-0.3.1',
      'parlance-0.3.0',
      'parlance-0.3.2',
    ], 'parlance-0.3.2');
    release('0.3.0', ['parlance-0.3.1', 'parlance-0.30.0'], null);
    release('0.3.0', ['parlance-0.3.0-beta.1'], null);
    release('0.3.0-beta.2', ['parlance-0.3.0', 'parlance-0.3.0-beta.1'], null);
    release('1.0.0', ['parlance-0.9.0'], null);
    release('1.2.0', [
      'parlance-1.0.0',
      'parlance-1.1.0',
      'parlance-0.9.0',
    ], 'parlance-1.1.0');
    release('2.0.0', ['parlance-1.9.0'], null);
    release('1.1.0', [
      'parlance_mcp-1.1.0',
      'parlance-no-version',
      'parlance-1.1.0-beta.1',
      'parlance-1.0.0',
    ], 'parlance-1.0.0');

    Future<void> check(String before, String now, bool compatible) async {
      final a = Directory('${root.path}/old${checked++}/lib')
        ..createSync(recursive: true);
      final b = Directory('${root.path}/new$checked/lib')
        ..createSync(recursive: true);
      File('${a.path}/schema.dart').writeAsStringSync(before);
      File('${b.path}/schema.dart').writeAsStringSync(now);
      final collection = AnalysisContextCollection(
        includedPaths: [a.path, b.path],
      );
      final breaks = frozenSurfaceBreaks(
        await surfaceOf(a.parent.path, collection),
        await surfaceOf(b.parent.path, collection),
        implemented: {'IWord', 'IServerStreamWord'},
      );
      if (breaks.isEmpty != compatible) {
        throw StateError('case $checked: $breaks');
      }
    }

    const old = 'class C { C(int x, {int n = 1}); }';
    await check(old, 'class C { C(int x, {int n = 1, String? label}); }', true);
    await check(old, 'class C { C(int x, {int n = 2}); }', false);
    await check(old, 'class C { C(int x, {num n = 1}); }', false);
    await check(
      old,
      'class C { C(int x, {int n = 1, required String label}); }',
      false,
    );
    await check(old, 'class C { C(int x, int y, {int n = 1}); }', false);
    await check(old, 'class C { C(int x); }', false);
    await check(
      'abstract interface class IWord {}',
      'abstract interface class IWord { String get name; }',
      false,
    );
    await check(
      'abstract interface class IWord {}',
      'abstract interface class IWord {} abstract interface class IServerStreamWord { String get name; }',
      true,
    );
    stdout.writeln('frozen surface: $checked checks passed');
  } finally {
    root.deleteSync(recursive: true);
  }
}
