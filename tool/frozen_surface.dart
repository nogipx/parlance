/// Source compatibility checks for the frozen public surface.
library;

import 'package:analyzer/dart/element/element.dart';

import 'surface.dart';

String _key(SurfaceItem i) =>
    '${i.library} ${i.name}'
    '${i.member == null ? '' : '.${i.member}'}';
String _line(SurfaceItem i) => '${_key(i)}: ${i.signature}';

/// Reports removals and changes, allowing additional optional named constructor
/// parameters. New interfaces may have members; existing implemented interfaces
/// may not gain any. Existing types, defaults and requiredness remain frozen.
List<String> frozenSurfaceBreaks(
  List<SurfaceItem> before,
  List<SurfaceItem> now, {
  required Set<String> implemented,
}) {
  final live = {for (final i in now) _key(i): i};
  final old = {for (final i in before) _key(i): i};
  return [
    for (final was in before)
      if (live[_key(was)] case final current?) ...[
        if (was.signature != current.signature &&
            !_optionalConstructorParameters(was, current))
          'gone or changed: ${_line(was)}',
      ] else
        'gone or changed: ${_line(was)}',
    for (final current in now)
      if (current.member != null &&
          !current.member!.startsWith('static ') &&
          implemented.contains(current.name) &&
          old.containsKey('${current.library} ${current.name}') &&
          !old.containsKey(_key(current)))
        'added to what an app implements: ${_line(current)}',
  ];
}

bool _optionalConstructorParameters(SurfaceItem before, SurfaceItem now) {
  final a = before.element;
  final b = now.element;
  if (a is! ConstructorElement || b is! ConstructorElement) return false;
  if (before.signature.split('(').first != now.signature.split('(').first) {
    return false;
  }
  final current = {for (final p in b.formalParameters) p.displayName: p};
  final names = {for (final p in a.formalParameters) p.displayName};
  for (final p in a.formalParameters) {
    if (current[p.displayName]?.displayString() != p.displayString()) {
      return false;
    }
  }
  final oldPositional = a.formalParameters
      .where((p) => p.isPositional)
      .map((p) => p.displayName)
      .join(',');
  final newPositional = b.formalParameters
      .where((p) => p.isPositional)
      .map((p) => p.displayName)
      .join(',');
  return oldPositional == newPositional &&
      b.formalParameters
          .where((p) => !names.contains(p.displayName))
          .every((p) => p.isOptionalNamed);
}
