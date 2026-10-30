/// The map of what the frozen libraries promise against the tests that
/// reach it (docs/протечки.md): each name of `schema.dart` and `app.dart`
/// and each public member, the test files whose code refers to it, and
/// whether a test reaches it at all, through the library's own code.
/// Written to docs/карта-поверхности.md, which git ignores: the code is
/// the truth, and a map kept in git would drift from it; this one is
/// written anew on each run, what no test reaches first.
///
/// Run from the repository's root:
///
///     fvm dart run tool/surface_map.dart
///
/// Each member is one of:
///
/// - touched: a test's code refers to it (`where` when
///   `test/contract/where_test.dart` does, so it is held in all four
///   places a part and its owner run);
/// - reached: no test names it, but what a test calls calls it, through
///   the library (a shape's `check`, run by the registry as a test
///   writes);
/// - none: no test reaches it.
///
/// What reaches what is read from the code, resolved: each declaration of
/// `packages/parlance/lib` leads to what its body refers to, and a member
/// to every member that overrides it (a call through `Shape.check` may run
/// any shape's), so `reached` says more than runs; `none` is sure. A test
/// that touches a member is no proof its promise holds either: what no
/// test reaches is unchecked for sure.
library;

import 'dart:collection';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

import 'surface.dart';

Future<void> main(List<String> args) async {
  final repo =
      (Process.runSync('git', ['rev-parse', '--show-toplevel']).stdout
              as String)
          .trim();
  final root = '$repo/packages/parlance';
  // The tests, by the label a file is shown with: the package's own, and
  // the generator's (its fixtures use what the annotations promise).
  final suites = {'': root, 'generator/': '$repo/packages/parlance_generator'};
  final collection = AnalysisContextCollection(
    includedPaths: [...suites.values],
  );
  // Each once: what `app.dart` shows again of `schema.dart` is that one's,
  // a field's getter is the field, and what the language makes on its own
  // (an enum's `values`, a constructor no one wrote) is no promise. A
  // name of another package (`LogScope`) is shown, its members are its.
  final seen = <String>{};
  final items = [
    for (final i in await surfaceOf(root, collection))
      if (!_implicit(i.element) &&
          (i.member == null || _ours(i.element)) &&
          !_ofObject.contains(i.member) &&
          seen.add('${i.member == null ? 'name ' : ''}${_key(i.element)}'))
        i,
  ];

  // The library's code: what each declaration leads to.
  final graph = _Graph();
  for (final f in _dartFiles('$root/lib')) {
    final unit = await _resolved(collection, f);
    if (unit != null) unit.accept(graph);
  }

  // The tests: which files refer to each element, and all they refer to,
  // the roots of what they reach.
  final usedBy = <String, Set<String>>{};
  final roots = <String>{};
  for (final MapEntry(key: label, value: package) in suites.entries) {
    // What frozen.dart unpacks there for a moment is no test.
    for (final f in _dartFiles('$package/test')) {
      if (f.contains('/_frozen_old/')) continue;
      final unit = await _resolved(collection, f);
      if (unit == null) continue;
      final refs = _Refs();
      unit.accept(refs);
      roots.addAll(refs.keys);
      final name = '$label${f.substring('$package/test/'.length)}';
      for (final k in refs.keys) {
        for (final up in graph.withSupers(k)) {
          (usedBy[up] ??= {}).add(name);
        }
      }
    }
  }
  final reached = graph.reachedFrom(roots);

  String? where(Set<String> files) =>
      files.contains('contract/where_test.dart') ? 'where' : null;
  Set<String> handOf(Iterable<String> files) => {
    for (final f in files)
      if (!f.endsWith('.g.dart')) f.replaceFirst('_test.dart', ''),
  };

  // A name is touched and reached through its members too: an
  // extension's never is named (`OwnerTools`), its members are.
  final throughMembers = <String, Set<String>>{};
  final reachedMembers = <String>{};
  for (final i in items) {
    if (i.member == null) continue;
    final of = '${i.library} ${i.name}';
    (throughMembers[of] ??= {}).addAll(usedBy[_key(i.element)] ?? const {});
    if (reached.contains(_key(i.element))) reachedMembers.add(of);
  }

  final table = StringBuffer();
  // What no test reaches, and what none names but the library reaches, by
  // name: the lists a pass takes its work from.
  final unreached = <String, List<String>>{};
  final throughLibrary = <String, List<String>>{};
  var touched = 0, held = 0, onlyReached = 0, none = 0;
  String? library;
  for (final i in items) {
    final of = '${i.library} ${i.name}';
    final key = _key(i.element);
    final files = {
      ...?usedBy[key],
      if (i.member == null) ...?throughMembers[of],
    };
    final hand = handOf(files);
    final isReached =
        reached.contains(key) ||
        (i.member == null && reachedMembers.contains(of));
    final String mark;
    if (hand.isNotEmpty) {
      touched++;
      if (where(files) != null) held++;
      mark = where(files) ?? '';
    } else if (isReached) {
      onlyReached++;
      mark = 'reached';
      (throughLibrary[of] ??= []).add(i.member ?? '(the name)');
    } else {
      none++;
      mark = 'none';
      (unreached[of] ??= []).add(i.member ?? '(the name)');
    }
    if (i.library != library) {
      library = i.library;
      table
        ..writeln('\n### $library\n')
        ..writeln('| member | tests | |')
        ..writeln('|---|---|---|');
    }
    final label = i.member == null ? '**${i.name}**' : '${i.name}.${i.member}';
    final shown = (hand.toList()..sort()).take(4).join(', ');
    final more = hand.length > 4 ? ' +${hand.length - 4}' : '';
    table.writeln('| $label | $shown$more | $mark |');
  }

  final summary =
      '${items.length} names and members: $touched touched by a test '
      '($held in where_test), $onlyReached reached only through the '
      'library, $none reached by none.';
  final map = StringBuffer()
    ..writeln('# The frozen surface and its tests')
    ..writeln()
    ..writeln(
      'Written by `tool/surface_map.dart` from the code; not kept in git, '
      'written anew on each run: edit nothing here. How to read it: '
      'docs/протечки.md.',
    )
    ..writeln()
    ..writeln(summary)
    ..writeln()
    ..writeln('## Reached by no test')
    ..writeln();
  for (final MapEntry(key: name, value: members) in unreached.entries) {
    map.writeln('- `$name`: ${members.join(', ')}');
  }
  map
    ..writeln()
    ..writeln('## Named by no test, reached through the library')
    ..writeln();
  for (final MapEntry(key: name, value: members) in throughLibrary.entries) {
    map.writeln('- `$name`: ${members.join(', ')}');
  }
  map
    ..writeln()
    ..writeln('## The whole surface')
    ..write(table);

  final file = File('$repo/docs/карта-поверхности.md')
    ..writeAsStringSync('$map');
  stdout
    ..writeln(summary)
    ..writeln('Written to ${file.path}.');
}

/// The Dart files under [dir], each once.
List<String> _dartFiles(String dir) => [
  for (final f in Directory(dir).listSync(recursive: true))
    if (f is File && f.path.endsWith('.dart')) f.path,
];

Future<CompilationUnit?> _resolved(
  AnalysisContextCollection collection,
  String path,
) async {
  final r = await collection
      .contextFor(path)
      .currentSession
      .getResolvedUnit(path);
  return r is ResolvedUnitResult ? r.unit : null;
}

/// What [e] stands for: a getter or a setter its field, a parameter
/// that sets a field (`this.callers`, as an annotation's named argument
/// names it) that field.
Element _standsFor(Element e) {
  var el = e.baseElement;
  while (true) {
    switch (el) {
      case PropertyAccessorElement(:final variable):
        el = variable.baseElement;
      case FieldFormalParameterElement(:final field?):
        el = field.baseElement;
      case SuperFormalParameterElement(:final superConstructorParameter?):
        el = superConstructorParameter.baseElement;
      default:
        return el;
    }
  }
}

/// What every object has: no promise of the library's, and called
/// unnamed (`expect`, a string's `\$x`), so no test would name it.
const _ofObject = {'toString', '==', 'hashCode', 'noSuchMethod', 'runtimeType'};

/// Whether the language made [e] on its own.
bool _implicit(Element e) => switch (_standsFor(e)) {
  ConstructorElement(:final isOriginImplicitDefault) => isOriginImplicitDefault,
  FieldElement(:final isOriginEnumValues) => isOriginEnumValues,
  _ => false,
};

/// Whether [e] is parlance's, not another package's it shows.
bool _ours(Element e) => '${e.library?.uri}'.startsWith('package:parlance/');

/// A key naming [e] the same wherever it is referred to: its library, what
/// declares it and its name.
String _key(Element e) {
  final el = _standsFor(e);
  final owner = el.enclosingElement;
  final at = owner is LibraryElement ? '' : '${owner?.name}.';
  final kind = el is ConstructorElement ? 'new ' : '';
  return '${el.library?.uri}#$kind$at${el.name}';
}

/// The elements a unit's code refers to, by key: every one of them, for a
/// test is reached as a whole.
final class _Refs extends RecursiveAstVisitor<void> {
  final Set<String> keys = {};

  /// Told [e]: what the code refers to.
  void refer(Element? e) {
    if (e != null) keys.add(_key(e));
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    refer(node.element);
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitNamedType(NamedType node) {
    refer(node.element);
    super.visitNamedType(node);
  }

  @override
  void visitConstructorName(ConstructorName node) {
    refer(node.element);
    super.visitConstructorName(node);
  }

  /// Each argument names the parameter it is for: a positional one too
  /// (`@CommandWord('turn')`, the word's `name`).
  @override
  void visitArgumentList(ArgumentList node) {
    for (final a in node.arguments) {
      refer(a.correspondingParameter);
    }
    super.visitArgumentList(node);
  }

  @override
  void visitAnnotation(Annotation node) {
    refer(node.element);
    super.visitAnnotation(node);
  }
}

/// The library's code as what leads to what: each declaration (a
/// function, a method, a constructor, a field with what sets it) to what
/// its code refers to, and each member to every member that overrides it.
final class _Graph extends _Refs {
  final Map<String, Set<String>> _to = {};

  /// Each member to the members it overrides: what runs it keeps their
  /// promise too (a test calling `RemoteSession.hears` holds
  /// `IRemoteSession.hears`).
  final Map<String, Set<String>> _up = {};

  /// [k] and every member it overrides, up the supertypes.
  Set<String> withSupers(String k) {
    final all = <String>{};
    final queue = Queue<String>.of([k]);
    while (queue.isNotEmpty) {
      final x = queue.removeFirst();
      if (all.add(x)) queue.addAll(_up[x] ?? const {});
    }
    return all;
  }

  /// The declaration whose code is being read; null between them.
  String? _at;

  void _edge(String from, String to) => (_to[from] ??= {}).add(to);

  @override
  void refer(Element? e) {
    if (e == null) return;
    final k = _key(e);
    // What a class's own code refers to outside any member (its
    // supertypes, a field's type) leads from the class.
    if (_at case final at?) _edge(at, k);
  }

  void _within(Element? declared, void Function() read) {
    final was = _at;
    if (declared != null) _at = _key(declared);
    read();
    _at = was;
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final c = node.declaredFragment?.element;
    if (c != null) _overrides(c);
    _within(c, () => super.visitClassDeclaration(node));
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    final m = node.declaredFragment?.element;
    if (m != null) _overrides(m);
    _within(m, () => super.visitMixinDeclaration(node));
  }

  @override
  void visitEnumDeclaration(EnumDeclaration node) {
    final e = node.declaredFragment?.element;
    if (e != null) _overrides(e);
    _within(e, () => super.visitEnumDeclaration(node));
  }

  @override
  void visitExtensionDeclaration(ExtensionDeclaration node) => _within(
    node.declaredFragment?.element,
    () => super.visitExtensionDeclaration(node),
  );

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) => _within(
    node.declaredFragment?.element,
    () => super.visitFunctionDeclaration(node),
  );

  @override
  void visitMethodDeclaration(MethodDeclaration node) => _within(
    node.declaredFragment?.element,
    () => super.visitMethodDeclaration(node),
  );

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) => _within(
    node.declaredFragment?.element,
    () => super.visitConstructorDeclaration(node),
  );

  /// A field's or a top-level variable's: what sets it is its own. A
  /// local one's is its function's.
  @override
  void visitVariableDeclaration(VariableDeclaration node) =>
      _within(switch (node.parent?.parent) {
        FieldDeclaration() ||
        TopLevelVariableDeclaration() => node.declaredFragment?.element,
        _ => null,
      }, () => super.visitVariableDeclaration(node));

  /// Each member of [c] that overrides one of a supertype's: reached from
  /// it, as a call through the supertype may run it.
  void _overrides(InterfaceElement c) {
    // Making one sets its fields, and makes it as its supertype too (a
    // `super()` no one wrote): what that runs is reached.
    for (final ctor in c.constructors) {
      for (final f in c.fields) {
        if (!f.isStatic) _edge(_key(ctor), _key(f));
      }
      for (final up
          in c.supertype?.element.constructors ??
              const <ConstructorElement>[]) {
        _edge(_key(ctor), _key(up));
      }
    }
    for (final m in [...c.methods, ...c.getters, ...c.setters]) {
      final name = m.name;
      if (name == null) continue;
      for (final s in c.allSupertypes) {
        final over = switch (m) {
          MethodElement() => s.element.getMethod(name),
          GetterElement() => s.element.getGetter(name),
          SetterElement() => s.element.getSetter(name),
          _ => null,
        };
        if (over != null) {
          _edge(_key(over), _key(m));
          (_up[_key(m)] ??= {}).add(_key(over));
        }
      }
    }
  }

  /// What [roots] reach, they with it, and what each overrides.
  Set<String> reachedFrom(Iterable<String> roots) {
    final reached = <String>{};
    final queue = Queue<String>.of(roots);
    while (queue.isNotEmpty) {
      final k = queue.removeFirst();
      if (!reached.add(k)) continue;
      queue
        ..addAll(_to[k] ?? const {})
        ..addAll(_up[k] ?? const {});
    }
    return reached;
  }
}
