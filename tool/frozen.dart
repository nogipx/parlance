/// Holds the public libraries to the latest compatible release. A new minor
/// before 1.0, or a new major from 1.0, may break the API. Within that line,
/// names and members remain compatible and generated words still build.
/// The baseline comes from its `parlance-<version>` tag, not a stored snapshot.
///
/// Run from the repository's root, before a release:
///
///     fvm dart run tool/frozen.dart              # latest compatible release
///     fvm dart run tool/frozen.dart --since <ref> # explicit comparison, any version
///
/// It prints what broke and exits 1. A new compatibility line without a release
/// has no baseline and passes; --since always performs the requested comparison.
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/error/error.dart';
import 'package:yaml/yaml.dart';

import 'surface.dart';
import 'frozen_surface.dart';

/// What an app's code or its generated code implements: a member added
/// to it breaks every class that does, so it is never added to.
const _implemented = {
  'IOwner',
  'IWord',
  'IStateWord',
  'ICommandWord',
  'IQueryWord',
  'IServerStreamWord',
  'IClientStreamWord',
  'IBidiStreamWord',
  'IFactWord',
};

Future<void> main(List<String> args) async {
  final repo = _git(['rev-parse', '--show-toplevel']).trim();
  final pubspec = loadYaml(
    File('$repo/packages/parlance/pubspec.yaml').readAsStringSync(),
  ) as YamlMap;
  final version = pubspec['version'] as String;
  final since = args.length == 2 && args.first == '--since'
      ? args.last
      : latestCompatibleRelease(
          version,
          _git(['tag', '--list', 'parlance-*']).trim().split('\n'),
        );
  if (since == null) {
    stdout.writeln(
      'frozen: no compatible release tag for $version; new API line',
    );
    return;
  }
  final sha = _git(['rev-parse', '--short', since]).trim();
  final old = Directory('${Directory(repo).parent.path}/.parlance_frozen_$sha');
  final broke = <String>[];
  try {
    if (old.existsSync()) _git(['worktree', 'remove', '--force', old.path]);
    _git(['worktree', 'add', '--detach', old.path, since]);
    _run('fvm', ['dart', 'pub', 'get'], old.path);
    final collection = AnalysisContextCollection(
      includedPaths: [
        '${old.path}/packages/parlance',
        '$repo/packages/parlance',
      ],
    );
    broke.addAll(
      frozenSurfaceBreaks(
        await surfaceOf('${old.path}/packages/parlance', collection),
        await surfaceOf('$repo/packages/parlance', collection),
        implemented: _implemented,
      ),
    );
    broke.addAll(await _oldGeneratedBuilds(repo, since));
  } finally {
    if (old.existsSync()) _git(['worktree', 'remove', '--force', old.path]);
  }
  if (broke.isEmpty) {
    stdout.writeln('frozen: nothing broke since $since');
    return;
  }
  stderr.writeln('frozen: broke since $since:');
  broke.forEach(stderr.writeln);
  exitCode = 1;
}

/// The generated code of the fixtures as they were at [since], built with
/// the library now: what does not build, by file.
Future<List<String>> _oldGeneratedBuilds(String repo, String since) async {
  const fixtures = 'packages/parlance_generator/test/fixtures';
  final into = Directory('$repo/packages/parlance_generator/test/_frozen_old');
  if (into.existsSync()) into.deleteSync(recursive: true);
  into.createSync(recursive: true);
  try {
    final tar = await Process.start('git', [
      'archive',
      since,
      fixtures,
    ], workingDirectory: repo);
    final untar = await Process.start('tar', [
      '-x',
      '--strip-components=4',
      '-C',
      into.path,
    ]);
    await tar.stdout.pipe(untar.stdin);
    await untar.exitCode;
    final files = [
      for (final f in into.listSync(recursive: true))
        if (f is File && f.path.endsWith('.dart')) f.path,
    ];
    if (files.isEmpty) return const [];
    final collection = AnalysisContextCollection(includedPaths: [into.path]);
    final broke = <String>[];
    for (final path in files) {
      final r = await collection
          .contextFor(path)
          .currentSession
          .getErrors(path);
      if (r is! ErrorsResult) continue;
      for (final d in r.diagnostics) {
        if (d.diagnosticCode.severity != DiagnosticSeverity.ERROR) continue;
        broke.add(
          'old generated code: ${path.substring(into.path.length + 1)}: '
          '${d.message}',
        );
      }
    }
    return broke;
  } finally {
    into.deleteSync(recursive: true);
  }
}

String _git(List<String> args) => _run('git', args, null);

String _run(String exe, List<String> args, String? dir) {
  final r = Process.runSync(exe, args, workingDirectory: dir);
  if (r.exitCode != 0) {
    throw ProcessException(exe, args, '${r.stderr}', r.exitCode);
  }
  return '${r.stdout}';
}
