/// The map of what the frozen libraries promise against the tests that
/// touch it (docs/протечки.md): each name of `schema.dart` and `app.dart`
/// and each public member, and the test files whose code refers to it,
/// resolved, not by its text; `where` when `test/contract/where_test.dart`
/// does, so it is held in all four places a part and its owner run.
/// Written to docs/карта-поверхности.md, which git ignores: the code is
/// the truth, and a map kept in git would drift from it; this one is
/// written anew on each run, what no test touches first.
///
/// Run, in packages/parlance_generator:
///
///     fvm dart run tool/surface_map.dart
///
/// A test that refers to a member is no proof its promise holds; one that
/// none refers to is unchecked for sure. Generated code (`.g.dart`) refers
/// to what a base or a client uses: counted apart, as `generated`.
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

import 'surface.dart';

Future<void> main(List<String> args) async {
  final root = Directory('../parlance').resolveSymbolicLinksSync();
  final collection = AnalysisContextCollection(includedPaths: [root]);
  // Each once: what `app.dart` shows again of `schema.dart` is that one's,
  // a field's getter is the field, and what the language makes on its own
  // (an enum's `values`, a constructor no one wrote) is no promise. A
  // name of another package (`LogScope`) is shown, its members are its.
  final seen = <String>{};
  final items = [
    for (final i in await surfaceOf(root, collection))
      if (!_implicit(i.element) &&
          (i.member == null || _ours(i.element)) &&
          seen.add('${i.member == null ? 'name ' : ''}${_key(i.element)}'))
        i,
  ];
  final wanted = {for (final i in items) _key(i.element)};

  // Which test files refer to each element, by its key.
  final usedBy = <String, Set<String>>{};
  final tests = Directory('$root/test')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();
  for (final f in tests) {
    final session = collection.contextFor(f.path).currentSession;
    final unit = await session.getResolvedUnit(f.path);
    if (unit is! ResolvedUnitResult) continue;
    final refs = _Refs();
    unit.unit.accept(refs);
    final name = f.path.substring('$root/test/'.length);
    for (final k in refs.keys) {
      if (wanted.contains(k)) (usedBy[k] ??= {}).add(name);
    }
  }

  String? where(Set<String> files) =>
      files.contains('contract/where_test.dart') ? 'where' : null;

  Set<String> handOf(Iterable<String> files) => {
    for (final f in files)
      if (!f.endsWith('.g.dart')) f.replaceFirst('_test.dart', ''),
  };
  // A name is touched through its members too: an extension's never is
  // named (`OwnerTools`), its members are.
  final throughMembers = <String, Set<String>>{};
  for (final i in items) {
    if (i.member == null) continue;
    (throughMembers['${i.library} ${i.name}'] ??= {}).addAll(
      usedBy[_key(i.element)] ?? const {},
    );
  }

  final table = StringBuffer();
  // What no test refers to, by name: the list a pass takes its work from.
  final untested = <String, List<String>>{};
  var touched = 0, held = 0, none = 0;
  String? library;
  for (final i in items) {
    final files = {
      ...?usedBy[_key(i.element)],
      if (i.member == null) ...?throughMembers['${i.library} ${i.name}'],
    };
    final hand = handOf(files);
    final generated = files.any((f) => f.endsWith('.g.dart'));
    if (hand.isEmpty) {
      none++;
      (untested['${i.library} ${i.name}'] ??= []).add(
        (i.member ?? '(the name)') + (generated ? ' (generated only)' : ''),
      );
    } else {
      touched++;
      if (where(files) != null) held++;
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
    final mark = hand.isEmpty
        ? (generated ? 'generated only' : 'none')
        : (where(files) ?? '');
    table.writeln('| $label | $shown$more | $mark |');
  }

  final summary =
      '${items.length} names and members: $touched touched by a test '
      '($held in where_test), $none by none.';
  final map = StringBuffer()
    ..writeln('# The frozen surface and its tests')
    ..writeln()
    ..writeln(
      'Written by `packages/parlance_generator/tool/surface_map.dart` from '
      'the code; not kept in git, written anew on each run: edit nothing '
      'here. How to read it: docs/протечки.md.',
    )
    ..writeln()
    ..writeln(summary)
    ..writeln()
    ..writeln('## Touched by no test')
    ..writeln();
  for (final MapEntry(key: name, value: members) in untested.entries) {
    map.writeln('- `$name`: ${members.join(', ')}');
  }
  map
    ..writeln()
    ..writeln('## The whole surface')
    ..write(table);

  final repo = Directory('../..').resolveSymbolicLinksSync();
  final file = File('$repo/docs/карта-поверхности.md')
    ..writeAsStringSync('$map');
  stdout
    ..writeln(summary)
    ..writeln('Written to ${file.path}.');
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

/// The elements a unit's code refers to, by key.
final class _Refs extends RecursiveAstVisitor<void> {
  final Set<String> keys = {};

  void _add(Element? e) {
    if (e != null) keys.add(_key(e));
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    _add(node.element);
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitNamedType(NamedType node) {
    _add(node.element);
    super.visitNamedType(node);
  }

  @override
  void visitConstructorName(ConstructorName node) {
    _add(node.element);
    super.visitConstructorName(node);
  }

  /// Each argument names the parameter it is for: a positional one too
  /// (`@CommandWord('turn')`, the word's `name`).
  @override
  void visitArgumentList(ArgumentList node) {
    for (final a in node.arguments) {
      _add(a.correspondingParameter);
    }
    super.visitArgumentList(node);
  }

  @override
  void visitAnnotation(Annotation node) {
    _add(node.element);
    super.visitAnnotation(node);
  }
}
