/// What the frozen libraries show: a name of
/// `package:parlance/schema.dart` or `app.dart`, and each public member of
/// it. Read from the code, kept nowhere: `frozen.dart` holds it to the
/// last release, `surface_map.dart` maps it to the tests.
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';

/// The frozen libraries, in `lib/`.
const frozen = ['schema.dart', 'app.dart'];

/// One thing a frozen library shows: a name ([member] null) or a member of
/// it, and the element it is.
typedef SurfaceItem = ({
  String library,
  String name,
  String? member,
  String signature,
  Element element,
});

/// What the frozen libraries of the package at [root] show, resolved in
/// [collection] (one that includes [root], so another file resolved there
/// names the same elements).
Future<List<SurfaceItem>> surfaceOf(
  String root,
  AnalysisContextCollection collection,
) async {
  final items = <SurfaceItem>[];
  for (final of in frozen) {
    final path = '$root/lib/$of';
    if (!File(path).existsSync()) continue;
    final session = collection.contextFor(path).currentSession;
    final lib = await session.getResolvedLibrary(path);
    if (lib is! ResolvedLibraryResult) continue;
    for (final MapEntry(key: name, value: e)
        in lib.element.exportNamespace.definedNames2.entries) {
      items.add((
        library: of,
        name: name,
        member: null,
        signature: e.displayString(),
        element: e,
      ));
      for (final m in membersOf(e)) {
        if (m.isPrivate) continue;
        final static = m is ExecutableElement && m.isStatic ? 'static ' : '';
        items.add((
          library: of,
          name: name,
          member: '$static${m.displayName}',
          signature: m.displayString(),
          element: m,
        ));
      }
    }
  }
  return items;
}

/// [surfaceOf] as lines, a line for each name and each public member, with
/// its signature: what a release is held to.
Future<Set<String>> surface(String root) async {
  final collection = AnalysisContextCollection(
    includedPaths: [for (final l in frozen) '$root/lib/$l'],
  );
  return {
    for (final i in await surfaceOf(root, collection))
      i.member == null
          ? '${i.library} ${i.name}: ${i.signature}'
          : '${i.library} ${i.name}.${i.member}: ${i.signature}',
  };
}

/// The members of [e] a library shows with it.
Iterable<Element> membersOf(Element e) => switch (e) {
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
