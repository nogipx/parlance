/// Holds the frozen libraries to the last release (docs/план-api.md, Д):
/// what `package:parlance/schema.dart` and `app.dart` show is never taken
/// away, renamed or changed, and a words package's `.g.dart` made then
/// builds with the library now. Nothing is kept in the repository to
/// compare with: the release is taken from its tag.
///
/// Run, in packages/parlance_generator, before a release:
///
///     fvm dart run tool/frozen.dart              # against the last v* tag
///     fvm dart run tool/frozen.dart --since <ref>
///
/// It prints what broke and exits 1; with no release yet, it says so and
/// passes.
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

const _frozen = ['schema.dart', 'app.dart'];

/// What an app's code or its generated code implements: a member added
/// to it breaks every class that does, so it is never added to.
const _implemented = {
  'IOwner',
  'IWord',
  'IStateWord',
  'ICommandWord',
  'IQueryWord',
  'IFactWord',
};

Future<void> main(List<String> args) async {
  final repo = _git(['rev-parse', '--show-toplevel']).trim();
  final since = args.length == 2 && args.first == '--since'
      ? args.last
      : _lastRelease();
  if (since == null) {
    stdout.writeln('frozen: no release tagged v* yet: nothing to hold to');
    return;
  }
  final sha = _git(['rev-parse', '--short', since]).trim();
  final old = Directory('${Directory(repo).parent.path}/.parlance_frozen_$sha');
  final broke = <String>[];
  try {
    if (old.existsSync()) _git(['worktree', 'remove', '--force', old.path]);
    _git(['worktree', 'add', '--detach', old.path, since]);
    _run('fvm', ['dart', 'pub', 'get'], old.path);
    final then = await surface('${old.path}/packages/parlance');
    final now = await surface('$repo/packages/parlance');
    final gone = then.difference(now).toList()..sort();
    for (final line in gone) {
      broke.add('gone or changed: $line');
    }
    final added = now.difference(then).where(_ofImplemented).toList()..sort();
    for (final line in added) {
      broke.add('added to what an app implements: $line');
    }
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

/// What the frozen libraries of the package at [root] show, a line for
/// each name and each public member, with its signature.
Future<Set<String>> surface(String root) async {
  final paths = [for (final l in _frozen) '$root/lib/$l'];
  final collection = AnalysisContextCollection(includedPaths: paths);
  final lines = <String>{};
  for (final (i, path) in paths.indexed) {
    if (!File(path).existsSync()) continue;
    final session = collection.contextFor(path).currentSession;
    final lib = await session.getResolvedLibrary(path);
    if (lib is! ResolvedLibraryResult) continue;
    final of = _frozen[i];
    for (final MapEntry(key: name, value: e)
        in lib.element.exportNamespace.definedNames2.entries) {
      lines.add('$of $name: ${e.displayString()}');
      for (final m in _members(e)) {
        if (m.isPrivate) continue;
        final static = m is ExecutableElement && m.isStatic ? 'static ' : '';
        lines.add('$of $name.$static${m.displayName}: ${m.displayString()}');
      }
    }
  }
  return lines;
}

/// Whether [line] is an instance member of what an app implements.
bool _ofImplemented(String line) {
  final at = line.indexOf(' ') + 1;
  final dot = line.indexOf('.', at);
  final colon = line.indexOf(':', at);
  if (dot < 0 || dot > colon) return false;
  return _implemented.contains(line.substring(at, dot)) &&
      !line.startsWith('static ', dot + 1);
}

Iterable<Element> _members(Element e) => switch (e) {
  final InterfaceElement c => [
    ...c.constructors,
    ...c.getters,
    ...c.setters,
    ...c.methods,
    if (c is EnumElement) ...c.constants,
  ],
  final ExtensionElement x => [...x.getters, ...x.setters, ...x.methods],
  _ => const [],
};

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

String? _lastRelease() {
  final tags = _git(['tag', '--list', 'v*', '--sort=-v:refname']).trim();
  return tags.isEmpty ? null : tags.split('\n').first;
}

String _git(List<String> args) => _run('git', args, null);

String _run(String exe, List<String> args, String? dir) {
  final r = Process.runSync(exe, args, workingDirectory: dir);
  if (r.exitCode != 0) {
    throw ProcessException(exe, args, '${r.stderr}', r.exitCode);
  }
  return '${r.stdout}';
}
