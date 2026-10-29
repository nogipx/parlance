import 'dart:async';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:dart_style/dart_style.dart';
import 'package:parlance/schema.dart';
import 'package:pub_semver/pub_semver.dart' show Version;
import 'package:source_gen/source_gen.dart';

/// What a name is (SPEC §1), as the generator tells it.
const _nameRule =
    'lower-case words split by ., each from a letter, joined by _ or - '
    '(audio.voice.muted_talk); a version, if any, last (.v2)';

const _state = TypeChecker.typeNamed(StateWord, inPackage: 'parlance');
const _command = TypeChecker.typeNamed(CommandWord, inPackage: 'parlance');
const _query = TypeChecker.typeNamed(QueryWord, inPackage: 'parlance');
const _fact = TypeChecker.typeNamed(FactWord, inPackage: 'parlance');
const _range = TypeChecker.typeNamed(Range, inPackage: 'parlance');
const _length = TypeChecker.typeNamed(Length, inPackage: 'parlance');
const _ref = TypeChecker.typeNamed(Ref, inPackage: 'parlance');
const _describe = TypeChecker.typeNamed(Describe, inPackage: 'parlance');
const _fieldName = TypeChecker.typeNamed(FieldName, inPackage: 'parlance');
const _default = TypeChecker.typeNamed(Default, inPackage: 'parlance');
const _millis = TypeChecker.typeNamed(Millis, inPackage: 'parlance');
const _fallback = TypeChecker.typeNamed(Fallback, inPackage: 'parlance');

/// Makes the typed words (SPEC §18, §23) of a class marked `@Vocabulary`:
/// an enum per kind of word it has, a record and its shape per params or
/// payload, and the vocabulary of them all (a `WordSet`).
final class VocabularyGenerator extends GeneratorForAnnotation<Vocabulary> {
  const VocabularyGenerator();

  /// Each vocabulary of the library: one library may say several (an index
  /// of parts, `part 'scenes.dart'`), so what they share (a record's shape,
  /// a class's `toJson`) is made once, in its one `.g.dart`.
  @override
  Future<String> generate(LibraryReader library, BuildStep buildStep) async {
    final shared = _Shared();
    return [
      for (final a in library.annotatedWith(typeChecker))
        await _generate(a.element, a.annotation, buildStep, shared),
    ].join('\n\n');
  }

  @override
  Future<String> generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) => _generate(element, annotation, buildStep, _Shared());

  Future<String> _generate(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
    _Shared shared,
  ) async {
    if (element is! ClassElement || !element.isAbstract) {
      throw InvalidGenerationSourceError(
        '@Vocabulary goes on an abstract class',
        element: element,
      );
    }
    final vocabulary = annotation.read('name').stringValue;
    if (!isValidName(vocabulary)) {
      throw InvalidGenerationSourceError(
        '@Vocabulary: "$vocabulary" is no name: $_nameRule',
        element: element,
      );
    }
    final out = _Emitter(
      element,
      vocabulary,
      owner: annotation.peek('owner')?.boolValue ?? true,
      client: annotation.peek('client')?.boolValue ?? true,
      recordFields: await _recordFields(element, buildStep.resolver),
      shared: shared,
      from: await _from(buildStep),
    ).build();
    return DartFormatter(languageVersion: Version(3, 9, 0)).format(out);
  }
}

/// The words package and its version, as the package's pubspec says
/// them (`notes_words 1.2.0`): what a client tells it was built against
/// (SPEC §6.9). Its name alone when the pubspec says no version or cannot
/// be read.
Future<String> _from(BuildStep step) async {
  final package = step.inputId.package;
  try {
    final pubspec = await step.readAsString(AssetId(package, 'pubspec.yaml'));
    final version = RegExp(
      r'''^version:\s*["']?([^\s"'#]+)''',
      multiLine: true,
    ).firstMatch(pubspec)?.group(1);
    return version == null ? package : '$package $version';
  } on Object {
    return package;
  }
}

/// The annotations on the named fields of each record typedef the words
/// of [cls] carry, by typedef and field: a record type keeps no metadata of
/// its own, so they are read from the typedef's source.
Future<Map<TypeAliasElement, Map<String, List<DartObject>>>> _recordFields(
  ClassElement cls,
  Resolver resolver,
) async {
  final out = <TypeAliasElement, Map<String, List<DartObject>>>{};
  final seen = <DartType>{};
  Future<void> visit(DartType t) async {
    if (!seen.add(t)) return;
    if (t is RecordType) {
      if (t.alias?.element case final a? when !out.containsKey(a)) {
        final fields = out[a] = {};
        final node = await resolver.astNodeFor(a.firstFragment, resolve: true);
        if (node case GenericTypeAlias(type: final RecordTypeAnnotation r)) {
          for (final RecordTypeAnnotationNamedField f
              in r.namedFields?.fields ?? const []) {
            fields[f.name.lexeme] = [
              for (final m in f.metadata)
                ?m.elementAnnotation?.computeConstantValue(),
            ];
          }
        }
      }
      for (final f in t.namedFields) {
        await visit(f.type);
      }
    }
    if (t is InterfaceType) {
      for (final a in t.typeArguments) {
        await visit(a);
      }
    }
  }

  for (final g in cls.getters) {
    await visit(g.returnType);
  }
  for (final m in cls.methods) {
    await visit(m.returnType);
    for (final p in m.formalParameters) {
      await visit(p.type);
    }
  }
  return out;
}

/// What the vocabularies of one library make once: the shapes of records,
/// by name, and the `toJson` tear-offs of classes.
final class _Shared {
  final Set<String> recordShapes = {};
  final Set<String> jsonHelpers = {};
}

/// A word as the class says it.
final class _Word {
  _Word(this.member, this.name, this.element);

  /// The enum value's name: the member's.
  final String member;
  final String name;
  final Element element;

  /// What the owner base passes to its `define`, as code: `readers:`,
  /// `callers:`, `deadline:`...
  final List<String> options = [];

  /// Whether the owner base asks `whyNot<Member>()` before a call.
  bool available = false;
}

final class _State extends _Word {
  _State(
    super.member,
    super.name,
    super.element,
    this.type,
    this.shape,
    this.key,
  );
  final String type;
  final String shape;
  final String? key;

  /// [key] as code: by the constant that names it, if any.
  String? keyCode;
}

final class _Callable extends _Word {
  _Callable(
    super.member,
    super.name,
    super.element,
    this.params,
    this.paramsShape,
    this.returns,
    this.returnsShape,
  );
  final String params;
  final String paramsShape;

  /// `void` and null for a command that answers nothing.
  final String returns;
  final String? returnsShape;

  /// What its handler returns, as the class declares it (`Future<void>`).
  late final String declared;
}

final class _Fact extends _Word {
  _Fact(super.member, super.name, super.element, this.type, this.shape);
  final String type;
  final String shape;
}

final class _Emitter {
  _Emitter(
    this.cls,
    this.vocabulary, {
    required this.owner,
    required this.client,
    required this.recordFields,
    required this.shared,
    required this.from,
  });

  final _Shared shared;

  /// The words package and its version ([_from]).
  final String from;

  final ClassElement cls;

  /// The annotations on each record typedef's fields ([_recordFields]).
  final Map<TypeAliasElement, Map<String, List<DartObject>>> recordFields;

  /// The shapes of the records made so far, by name: each made once.
  Set<String> get _recordShapes => shared.recordShapes;
  final String vocabulary;
  final bool owner;
  final bool client;

  String get _c => cls.name!;

  /// The vocabulary's constant: `playerWords` of `Player`.
  String get _words => '${_c[0].toLowerCase()}${_c.substring(1)}Words';

  /// Code after the enums: records, their conversions, toJson tear-offs.
  final StringBuffer _helpers = StringBuffer();

  /// The record each generated record's name stands for: `({int volume})`
  /// of `PlayerClipped`, for what must say no name of the generated file.
  final Map<String, String> _inline = {};
  Set<String> get _jsonHelpers => shared.jsonHelpers;

  String build() {
    final states = <_State>[];
    final commands = <_Callable>[];
    final queries = <_Callable>[];
    final facts = <_Fact>[];
    final names = <String, Element>{};

    void named(_Word w) {
      if (names[w.name] case final other?) {
        throw InvalidGenerationSourceError(
          '${w.name} is said twice: by ${other.displayName} and '
          '${w.element.displayName}',
          element: w.element,
        );
      }
      names[w.name] = w.element;
    }

    for (final g in cls.getters) {
      if (!g.isOriginDeclaration || g.isStatic) continue;
      final a = _state.firstAnnotationOf(g);
      if (a == null) {
        if (g.isAbstract) _unmarked(g);
        continue;
      }
      final r = ConstantReader(a);
      final s =
          _State(
              g.displayName,
              _name(g, r),
              g,
              _dart(g.returnType),
              _shape(g.returnType, g, g.displayName),
              r.peek('key')?.stringValue,
            )
            ..keyCode = switch (r.peek('key')) {
              final k? => _code(k.objectValue, _quote(k.stringValue)),
              null => null,
            };
      if (r.peek('readers')?.objectValue case final o?) {
        s.options.add('readers: ${_callers(o)}');
      }
      _meta(s, r);
      named(s);
      states.add(s);
    }
    for (final m in cls.methods) {
      if (m.isStatic) continue;
      if (_command.firstAnnotationOf(m) case final a?) {
        final r = ConstantReader(a);
        final c = _callable(m, r, query: false);
        if (r.peek('callers')?.objectValue case final o?) {
          c.options.add('callers: ${_callers(o)}');
        }
        _common(c, r);
        _meta(c, r);
        named(c);
        commands.add(c);
      } else if (_query.firstAnnotationOf(m) case final a?) {
        final r = ConstantReader(a);
        final q = _callable(m, r, query: true);
        if (r.peek('askers')?.objectValue case final o?) {
          q.options.add('askers: ${_callers(o)}');
        }
        _common(q, r);
        _meta(q, r);
        named(q);
        queries.add(q);
      } else if (_fact.firstAnnotationOf(m) case final a?) {
        final r = ConstantReader(a);
        final f = _factOf(m, r);
        if (r.peek('readers')?.objectValue case final o?) {
          f.options.add('readers: ${_callers(o)}');
        }
        if (r.peek('open')?.boolValue ?? false) f.options.add('open: true');
        _meta(f, r);
        named(f);
        facts.add(f);
      } else if (m.isAbstract) {
        _unmarked(m);
      }
    }
    if (names.isEmpty) {
      throw InvalidGenerationSourceError(
        '$_c says no word: mark its members @StateWord, @CommandWord, '
        '@QueryWord or @FactWord',
        element: cls,
      );
    }

    final out = StringBuffer();
    if (states.isNotEmpty) out.write(_statesEnum(states));
    if (commands.isNotEmpty) {
      out.write(_callablesEnum('${_c}Command', 'ICommandWord', commands));
    }
    if (queries.isNotEmpty) {
      out.write(_callablesEnum('${_c}Query', 'IQueryWord', queries));
    }
    if (facts.isNotEmpty) out.write(_factsEnum(facts));
    if (owner) out.write(_ownerBase(states, commands, queries, facts));
    if (client) out.write(_clientOf(states, commands, queries, facts));
    out
      ..writeln('/// The vocabulary of [$_c]: its name and every word, for')
      ..writeln('/// `main` to grant a participant (`vocabularies:`) and for')
      ..writeln('/// `schemaOf`.')
      ..writeln('const $_words = WordSet(${_quote(vocabulary)}, [')
      ..writeln(
        [
          if (states.isNotEmpty) '...${_c}State.values',
          if (commands.isNotEmpty) '...${_c}Command.values',
          if (queries.isNotEmpty) '...${_c}Query.values',
          if (facts.isNotEmpty) '...${_c}Fact.values',
        ].join(', '),
      )
      ..writeln('], from: ${_quote(from)});')
      ..write(_helpers);
    return out.toString();
  }

  Never _unmarked(Element e) => throw InvalidGenerationSourceError(
    '${e.displayName} is abstract but no word: mark it @StateWord, '
    '@CommandWord, @QueryWord or @FactWord',
    element: e,
  );

  String _name(Element e, ConstantReader r) {
    final own = r.peek('name')?.stringValue ?? _snake(e.displayName);
    // '' is the vocabulary itself: `signal`, beside `signal.raise`.
    final name = own.isEmpty ? vocabulary : '$vocabulary.$own';
    try {
      checkWordName(name);
    } on ArgumentError catch (x) {
      throw InvalidGenerationSourceError(
        '${e.displayName}: "$name" is no word name: ${x.message}. $_nameRule',
        element: e,
      );
    }
    return name;
  }

  _Callable _callable(
    MethodElement m,
    ConstantReader r, {
    required bool query,
  }) {
    for (final p in m.formalParameters) {
      if (!p.isNamed) {
        throw InvalidGenerationSourceError(
          '${m.displayName}: params are named parameters, ${p.displayName} '
          'is positional',
          element: p,
        );
      }
    }
    final (params, paramsShape) = _record(m, m.formalParameters);
    final returned = _unwrapFuture(m.returnType);
    if (returned is VoidType && query) {
      throw InvalidGenerationSourceError(
        '${m.displayName}: a query answers; give it a return type',
        element: m,
      );
    }
    return _Callable(
      m.displayName,
      _name(m, r),
      m,
      params,
      paramsShape,
      returned is VoidType ? 'void' : _dart(returned),
      returned is VoidType ? null : _shape(returned, m, m.displayName),
    )..declared = _dart(m.returnType);
  }

  /// A command's or a query's deadline and availability.
  void _common(_Word w, ConstantReader r) {
    if (r.peek('deadline')?.objectValue case final o?) {
      final us = o.getField('inMicroseconds')?.toIntValue();
      w.options.add('deadline: const Duration(microseconds: $us)');
    }
    w.available = r.peek('available')?.boolValue ?? false;
  }

  /// A word's `meta`, when it has one.
  void _meta(_Word w, ConstantReader r) {
    final m = r.peek('meta')?.objectValue;
    if (m == null || (m.toMapValue()?.isEmpty ?? true)) return;
    w.options.add('meta: ${_code(m, 'const ${_constant(m, w.element)}')}');
  }

  /// [o], a constant of JSON, as code: a text, a number, a bool, null, and
  /// lists and maps of them.
  String _constant(DartObject o, Element at) {
    if (o.isNull) return 'null';
    final t = o.type;
    if (t != null && t.isDartCoreString) return _quote(o.toStringValue()!);
    if (t != null && t.isDartCoreBool) return '${o.toBoolValue()}';
    if (t != null && t.isDartCoreInt) return '${o.toIntValue()}';
    if (t != null && t.isDartCoreDouble) return '${o.toDoubleValue()}';
    if (o.toListValue() case final l?) {
      return '[${[for (final e in l) _constant(e, at)].join(', ')}]';
    }
    if (o.toMapValue() case final m?) {
      return '{${[for (final MapEntry(:key, :value) in m.entries) '${_constant(key!, at)}: ${_constant(value!, at)}'].join(', ')}}';
    }
    throw InvalidGenerationSourceError(
      'meta holds JSON: texts, numbers, bools, lists and maps of them',
      element: at,
    );
  }

  /// [o] as code: the constant it was named by (`Who.crew`, `minDb`), so
  /// the generated code follows it; else [literal].
  String _code(DartObject o, String literal) {
    final v = o.variable;
    if (v == null || !v.isConst) return literal;
    return switch (v.enclosingElement) {
      final InterfaceElement e when _sees(e) =>
        '${e.displayName}.${v.displayName}',
      LibraryElement() when _sees(v) => v.displayName,
      _ => literal,
    };
  }

  /// Whether the generated part names [e] by its name alone: it is the
  /// library's, or imported with no prefix.
  bool _sees(Element e) =>
      switch (cls.library.firstFragment.scope.lookup(e.displayName).getter) {
        final GetterElement g => g.variable == e,
        final found => found == e,
      };

  /// [o], a `Callers`, as code: by the constant that names it, if any.
  String _callers(DartObject o) => _code(o, _callersLiteral(o));

  String _callersLiteral(DartObject o) {
    final rules = o.getField('rules')?.toMapValue() ?? const {};
    final entries = [
      for (final MapEntry(:key, :value) in rules.entries)
        '${_quote(key!.toStringValue()!)}: Access.${value!.variable?.name}',
    ];
    return 'const Callers({${entries.join(', ')}})';
  }

  /// `<Class>Client` (SPEC §23.5): the words as a consumer uses them, over
  /// a view (a participant, `LocalView`, `MirrorView`): states read and
  /// watched, commands and queries as methods of the class's params that
  /// answer or throw [CallNotDone], facts as streams of their payloads.
  /// What uses it takes `I<Class>Client`, the same members as an
  /// interface, so a test or another source of the words stands in.
  String _clientOf(
    List<_State> states,
    List<_Callable> commands,
    List<_Callable> queries,
    List<_Fact> facts,
  ) {
    final members = <String, Element>{};
    void member(String name, _Word w) {
      if (const {
            'view',
            'status',
            'statusChanges',
            'mismatches',
          }.contains(name) ||
          members.containsKey(name)) {
        throw InvalidGenerationSourceError(
          '$name is had twice by ${_c}Client: name ${w.member} otherwise, or '
          '@Vocabulary(client: false)',
          element: w.element,
        );
      }
      members[name] = w.element;
    }

    // Each member once: what it says, its signature, and its body in the
    // client over a view. The interface says only Dart's types and the
    // vocabulary's own; what is parlance's (a word's status, a fact's
    // message) is the client's alone.
    final all = <({List<String> docs, String signature, String body})>[];
    final own = <({List<String> docs, String signature, String body})>[
      (
        docs: [
          'Whether [word] is there for the view now, as this code was built',
          'against it: `WordMismatch`, saying where, when not (SPEC §6.5).',
        ],
        signature: 'WordStatus status(IWord word)',
        body: '=> wordStatus(view, word);',
      ),
      (
        docs: ['[status], then whenever it changes.'],
        signature: 'Stream<WordStatus> statusChanges(IWord word)',
        body: '=> wordStatusChanges(view, word);',
      ),
      (
        docs: [
          'Each word of [$_c] there but not as this code was built against,',
          'with where it breaks; empty when all keep their promises. For a',
          'start in development: `assert(client.mismatches.isEmpty)`.',
        ],
        signature: 'Map<String, List<WordBreak>> get mismatches',
        body: '=> wordMismatches(view, $_words.words);',
      ),
    ];
    for (final st in states) {
      final word = '${_c}State.${st.member}';
      final bare = st.type.endsWith('?')
          ? st.type.substring(0, st.type.length - 1)
          : st.type;
      if (st.key == null) {
        member(st.member, st);
        member('${st.member}Changes', st);
        all
          ..add((
            docs: ['${st.name} now.'],
            signature: '$bare? get ${st.member}',
            body: '=> view.state($word).read();',
          ))
          ..add((
            docs: ['${st.name} now, then whenever it changes.'],
            signature: 'Stream<$bare?> get ${st.member}Changes',
            body: '=> view.state($word).watch();',
          ));
      } else {
        final key = _keyParam(st.key!);
        member('${st.member}Of', st);
        member('${st.member}All', st);
        member('${st.member}Changes', st);
        all
          ..add((
            docs: ['${st.name} of [$key] now.'],
            signature: '$bare? ${st.member}Of(String $key)',
            body: '=> view.state($word).read(key: $key);',
          ))
          ..add((
            docs: ['${st.name} of every ${st.key}, by key.'],
            signature: 'Map<String?, ${st.type}> get ${st.member}All',
            body: '=> view.state($word).readAll();',
          ))
          ..add((
            docs: ['${st.name} of [$key] now, then on every change.'],
            signature: 'Stream<$bare?> ${st.member}Changes(String $key)',
            body: '=> view.state($word).watch(key: $key);',
          ));
      }
    }
    for (final (kind, words) in [('Command', commands), ('Query', queries)]) {
      for (final c in words) {
        member(c.member, c);
        final ps = (c.element as MethodElement).formalParameters;
        final signature = ps.isEmpty ? '' : '{${ps.map(_param).join(', ')}}';
        final record = _recordOf(ps);
        final how = kind == 'Command' ? 'command' : 'query';
        final act = kind == 'Command' ? 'call' : 'ask';
        all.add((
          docs: [
            '${kind == 'Command' ? 'Calls' : 'Asks'} ${c.name}; a call not '
                'done throws [CallNotDone].',
          ],
          signature: 'Future<${c.returns}> ${c.member}($signature)',
          body:
              'async {\n'
              '    final r = await view.$how($_c$kind.${c.member}).$act($record);\n'
              '    if (r case CallDone(:final value)) return value;\n'
              '    throw CallNotDone(r);\n'
              '  }',
        ));
      }
    }
    for (final f in facts) {
      member(f.member, f);
      member('${f.member}Facts', f);
      final payload = _inline[f.type] ?? f.type;
      all.add((
        docs: ['${f.name}, as it is said from now on: what it says.'],
        signature: 'Stream<$payload> get ${f.member}',
        body:
            '=> view.fact(${_c}Fact.${f.member}).stream.map((f) => f.payload);',
      ));
      own.add((
        docs: [
          '${f.name}, as it is said from now on: its payload, and',
          'the message (its id, its cause) to follow it from.',
        ],
        signature: 'Stream<Fact<${f.type}>> get ${f.member}Facts',
        body: '=> view.fact(${_c}Fact.${f.member}).stream;',
      ));
    }

    final out = StringBuffer()
      ..writeln('/// The words of [$_c] as a consumer uses them: what a part')
      ..writeln('/// that uses them takes, so a stand-in can be given in its')
      ..writeln('/// place. [${_c}Client] is them over a view.')
      ..writeln('abstract interface class I${_c}Client {');
    for (final (i, m) in all.indexed) {
      if (i > 0) out.writeln();
      for (final d in m.docs) {
        out.writeln('  /// $d');
      }
      out.writeln('  ${m.signature};');
    }
    out
      ..writeln('}')
      ..writeln()
      ..writeln('/// The words of [$_c] through a view: its participant, a')
      ..writeln('/// `LocalView`, a `MirrorView`. Made, it tells the registry')
      ..writeln('/// the code was built against them, for it to say where one')
      ..writeln('/// is defined otherwise (SPEC §6.9).')
      ..writeln('final class ${_c}Client implements I${_c}Client {')
      ..writeln('  ${_c}Client(this.view) {')
      ..writeln('    view.builtAgainst($_words.words, from: $_words.from);')
      ..writeln('  }')
      ..writeln()
      ..writeln('  final IRegistryView view;');
    for (final m in all) {
      out
        ..writeln()
        ..writeln('  @override')
        ..writeln('  ${m.signature} ${m.body}');
    }
    for (final m in own) {
      out.writeln();
      for (final d in m.docs) {
        out.writeln('  /// $d');
      }
      out.writeln('  ${m.signature} ${m.body}');
    }
    out
      ..writeln('}')
      ..writeln();
    return out.toString();
  }

  /// [p] as the class declares it: `required int volume`, `int count = 1`.
  String _param(FormalParameterElement p) =>
      '${p.isRequired ? 'required ' : ''}${_dart(p.type)} ${p.displayName}'
      '${p.defaultValueCode == null ? '' : ' = ${p.defaultValueCode}'}';

  /// The record of [ps]'s values: `(volume: volume)`, `()`.
  String _recordOf(List<FormalParameterElement> ps) => ps.isEmpty
      ? '()'
      : '(${[for (final p in ps) '${p.displayName}: ${p.displayName}'].join(', ')})';

  /// A key's parameter: the kind's name in camel case.
  String _keyParam(String kind) {
    final parts = kind.split(RegExp('[._-]'));
    return parts.first + parts.skip(1).map(_pascal).join();
  }

  /// The names an owner base has of [Owner]'s own.
  static const _ownerMembers = {
    'define',
    'defineMore',
    'sync',
    'keep',
    'listen',
    'trackKind',
    'participant',
    'dispose',
    'changes',
    'attach',
    'hashCode',
    'runtimeType',
    'toString',
    'noSuchMethod',
  };

  /// `<Class>Owner` (SPEC §23.4): an owner base that defines every word,
  /// keeps a writer of each state and an emitter of each fact, and asks a
  /// handler of each command and query, for the owner to write.
  String _ownerBase(
    List<_State> states,
    List<_Callable> commands,
    List<_Callable> queries,
    List<_Fact> facts,
  ) {
    for (final w in [...states, ...commands, ...queries, ...facts]) {
      if (_ownerMembers.contains(w.member)) {
        throw InvalidGenerationSourceError(
          '${w.member} is a member of Owner: name it otherwise, or '
          '@Vocabulary(owner: false)',
          element: w.element,
        );
      }
    }
    String opts(_Word w) => [
      ...w.options,
      if (w.available) 'available: whyNot${_pascal(w.member)}',
    ].join(', ');
    final out = StringBuffer()
      ..writeln('/// The owner base of [$_c]: it defines every word, keeps a')
      ..writeln('/// writer of each state, says each fact by a method of its')
      ..writeln('/// params, and serves each command and query by a handler to')
      ..writeln(
        '/// write (`call.inReply`: the cause of what it does in reply).',
      )
      ..writeln('abstract base class ${_c}Owner extends Owner {');
    for (final st in states) {
      out
        ..writeln('  /// Writes ${st.name}.')
        ..writeln('  late final StateWriterOf<${st.type}> ${st.member};');
    }
    for (final f in facts) {
      out.writeln('  late final FactEmitterOf<${f.type}> _${f.member};');
    }
    out
      ..writeln()
      ..writeln('  @override')
      ..writeln('  void define(IParticipant p) {');
    for (final st in states) {
      out.writeln(
        '    ${st.member} = keep(p.state(${_c}State.${st.member})'
        '.define(${opts(st)}));',
      );
    }
    for (final f in facts) {
      out.writeln(
        '    _${f.member} = keep(p.fact(${_c}Fact.${f.member})'
        '.define(${opts(f)}));',
      );
    }
    for (final c in commands) {
      out.writeln(
        '    keep(p.command(${_c}Command.${c.member})'
        '.define(${[c.member, opts(c)].where((x) => x.isNotEmpty).join(', ')}));',
      );
    }
    for (final q in queries) {
      out.writeln(
        '    keep(p.query(${_c}Query.${q.member})'
        '.define(${[q.member, opts(q)].where((x) => x.isNotEmpty).join(', ')}));',
      );
    }
    out
      ..writeln('    defineMore(p);')
      ..writeln('  }')
      ..writeln()
      ..writeln();
    for (final f in facts) {
      final ps = (f.element as MethodElement).formalParameters;
      if (ps.any((p) => p.displayName == 'cause')) {
        throw InvalidGenerationSourceError(
          '${f.member}: a fact\'s param is not named cause, its owner base '
          'says one',
          element: f.element,
        );
      }
      final positional = ps.length == 1 && ps.single.isPositional;
      final signature = positional
          ? '${_dart(ps.single.type)} ${ps.single.displayName}, '
                '{Cause? cause}'
          : '{${[for (final p in ps) _param(p), 'Cause? cause'].join(', ')}}';
      final payload = positional ? ps.single.displayName : _recordOf(ps);
      out
        ..writeln('  /// Says ${f.name}; [cause] as a write\'s.')
        ..writeln(
          '  void ${f.member}($signature) =>'
          ' _${f.member}.emit($payload, cause: cause);',
        )
        ..writeln();
    }
    out
      ..writeln('  /// What [$_c] does not say: kinds, guards, words named at')
      ..writeln('  /// run time. After its words are defined.')
      ..writeln('  void defineMore(IParticipant p) {}');
    for (final c in commands) {
      out
        ..writeln()
        ..writeln('  /// Serves ${c.name}.')
        ..writeln(
          '  ${c.declared} ${c.member}(CommandCallOf<${c.params}> call);',
        );
      if (c.available) {
        out
          ..writeln()
          ..writeln('  /// Why ${c.name} cannot run now; null when it can.')
          ..writeln('  String? whyNot${_pascal(c.member)}();');
      }
    }
    for (final q in queries) {
      out
        ..writeln()
        ..writeln('  /// Answers ${q.name}.')
        ..writeln('  ${q.declared} ${q.member}(QueryAsk<${q.params}> ask);');
      if (q.available) {
        out
          ..writeln()
          ..writeln(
            '  /// Why ${q.name} cannot be asked now; null when it can.',
          )
          ..writeln('  String? whyNot${_pascal(q.member)}();');
      }
    }
    out
      ..writeln('}')
      ..writeln();
    return out.toString();
  }

  _Fact _factOf(MethodElement m, ConstantReader r) {
    if (m.returnType is! VoidType) {
      throw InvalidGenerationSourceError(
        '${m.displayName}: a fact returns void; its parameters are what it '
        'says',
        element: m,
      );
    }
    final ps = m.formalParameters;
    if (ps.length == 1 && ps.single.isPositional) {
      final p = ps.single;
      return _Fact(
        m.displayName,
        _name(m, r),
        m,
        _dart(p.type),
        _shape(p.type, p, p.displayName),
      );
    }
    for (final p in ps) {
      if (!p.isNamed) {
        throw InvalidGenerationSourceError(
          '${m.displayName}: a payload is named parameters, or one '
          'positional',
          element: p,
        );
      }
    }
    final (type, shape) = _record(m, ps);
    return _Fact(m.displayName, _name(m, r), m, type, shape);
  }

  /// The record of [ps] (`({int volume})`, named `<Class><Member>`) and its
  /// shape; no parameters: `()` and `RecordShape.none`.
  (String, String) _record(MethodElement m, List<FormalParameterElement> ps) {
    if (ps.isEmpty) return ('()', 'RecordShape.none');
    final rec = '$_c${_pascal(m.displayName)}';
    final fields = <String>[];
    final parts = <String>[];
    final to = <String>[];
    final from = <String>[];
    final at = <String>[];
    for (final p in ps) {
      final n = p.displayName;
      final key = _jsonName(p);
      final type = _dart(p.type);
      fields.add('$type $n');
      final nullable = p.type.nullabilitySuffix == NullabilitySuffix.question;
      final dflt = p.defaultValueCode;
      // One left out may be absent: its shape is the value's. A required
      // one that may be null says null (SPEC §18).
      final optional = dflt != null || !p.isRequired;
      final shape = _shape(
        optional && nullable ? _nonNull(p.type) : p.type,
        p,
        '${m.displayName}.$n',
      );
      final args = [
        shape,
        if (optional && dflt == null) 'optional: true',
        if (dflt != null) 'defaultValue: ${_json(p)}',
        if (_describeOf(_describe.firstAnnotationOf(p)) case final d?)
          'description: $d',
      ];
      parts.add('${_quote(key)}: Part(${args.join(', ')})');
      to.add('${_quote(key)}: p.$n');
      at.add('p.$n');
      final bare = _dart(p.type).replaceFirst(RegExp(r'\?$'), '');
      from.add(switch ((nullable, dflt)) {
        (_, final String d) => '$n: (m[${_quote(key)}] as $bare?) ?? $d',
        (true, null) when bare == 'Object' => '$n: m[${_quote(key)}]',
        (true, null) => '$n: m[${_quote(key)}] as $bare?',
        (false, null) => '$n: m[${_quote(key)}]! as $bare',
      });
    }
    _inline[rec] = '({${fields.join(', ')}})';
    _helpers
      ..writeln()
      ..writeln('typedef $rec = ({${fields.join(', ')}});')
      ..writeln()
      ..writeln(
        'Map<String, Object?> _\$${rec}To($rec p) => {${to.join(', ')}};',
      )
      ..writeln()
      ..writeln(
        '$rec _\$${rec}From(Map<String, Object?> m) => (${from.join(', ')});',
      )
      ..writeln()
      ..writeln('Object? _\$${rec}At($rec p, int i) => ${_byPlace(at)};');
    return (
      rec,
      'RecordShape<$rec>({${parts.join(', ')}}, '
          'to: _\$${rec}To, from: _\$${rec}From, get: _\$${rec}At)',
    );
  }

  /// A field read by its place: each of [fields] by its index, so a
  /// record shape reads a value with no map made of it (SPEC §18).
  static String _byPlace(List<String> fields) => switch (fields.length) {
    0 => 'null',
    1 => fields.single,
    _ =>
      'switch (i) {${[for (final (i, f) in fields.indexed) i == fields.length - 1 ? '_ => $f' : '$i => $f'].join(', ')}}',
  };

  /// A parameter's default as JSON, for its part.
  String _json(FormalParameterElement p) {
    final v = p.computeConstantValue();
    if (v == null) {
      throw InvalidGenerationSourceError(
        '${p.displayName}: its default is not a constant',
        element: p,
      );
    }
    if (v.type?.element case EnumElement()) {
      return "'${v.variable?.name ?? v.getField('_name')?.toStringValue()}'";
    }
    if (v.toBoolValue() case final b?) return '$b';
    if (v.toIntValue() case final i?) return '$i';
    if (v.toDoubleValue() case final d?) return '$d';
    if (v.toStringValue() case final s?) return _quote(s);
    if (v.isNull) return 'null';
    if (v.toListValue() != null || v.toMapValue() != null) {
      return 'const ${_constant(v, p)}';
    }
    throw InvalidGenerationSourceError(
      '${p.displayName}: a default here is a bool, a number, a text, an '
      'enum value, or a list or a map of them',
      element: p,
    );
  }

  /// The name [p] has in JSON: its `@FieldName`, else its own.
  String _jsonName(FormalParameterElement p) =>
      switch (_fieldName.firstAnnotationOf(p)) {
        final a? => ConstantReader(a).read('name').stringValue,
        null => p.displayName,
      };

  /// A `@Describe`'s text as code, if [a] is one.
  String? _describeOf(DartObject? a) => switch (a) {
    final a? => _quote(ConstantReader(a).read('text').stringValue),
    null => null,
  };

  /// The shape of [t] (SPEC §18), as code in a constant context; [on]
  /// carries its bounds.
  ///
  /// [notes], when given, are the annotations in place of [on]'s: a record
  /// field's, which has no element of its own.
  String _shape(
    DartType t,
    Element on,
    String where, {
    bool bounded = true,
    List<DartObject>? notes,
  }) {
    // Any value, null too.
    if (t is DynamicType || (t is InterfaceType && t.isDartCoreObject)) {
      return 'Plain(AnyType())';
    }
    if (t.nullabilitySuffix == NullabilitySuffix.question) {
      final inner = _nonNull(t);
      return 'Nullable<${_dart(inner)}>('
          '${_shape(inner, on, where, bounded: bounded, notes: notes)})';
    }
    DartObject? note(TypeChecker c) => !bounded
        ? null
        : notes == null
        ? c.firstAnnotationOf(on)
        : notes
              .where((o) => o.type != null && c.isExactlyType(o.type!))
              .firstOrNull;
    final range = note(_range);
    final length = note(_length);
    final ref = note(_ref);
    final millis = note(_millis);
    final max = length == null
        ? null
        : _code(
            ConstantReader(length).read('max').objectValue,
            '${ConstantReader(length).read('max').intValue}',
          );
    String bounds(String type) {
      if (range == null) return '$type()';
      final r = ConstantReader(range);
      final min = r.peek('min')?.literalValue;
      final mx = r.peek('max')?.literalValue;
      if (type == 'IntType' && (min is double || mx is double)) {
        throw InvalidGenerationSourceError(
          '$where: an int has int bounds',
          element: on,
        );
      }
      return '$type(${[if (min != null) 'min: ${_code(r.read('min').objectValue, '$min')}', if (mx != null) 'max: ${_code(r.read('max').objectValue, '$mx')}'].join(', ')})';
    }

    if (t.isDartCoreBool) return 'Plain(BoolType())';
    if (t.isDartCoreInt && millis != null) {
      final max = ConstantReader(millis).peek('max');
      return 'Plain(DurationType(${max == null ? '' : 'max: ${_code(max.objectValue, '${max.intValue}')}'}))';
    }
    if (t.isDartCoreInt) return 'Plain(${bounds('IntType')})';
    if (t.isDartCoreDouble) {
      throw InvalidGenerationSourceError(
        '$where: a number a word carries is num or int, not double (JSON '
        'does not keep 1.0 apart from 1)',
        element: on,
      );
    }
    if (t.isDartCoreNum) return 'Plain(${bounds('NumType')})';
    if (t.isDartCoreString) {
      if (ref != null) {
        final kind = ConstantReader(ref).read('kind');
        return 'Plain(RefType(${_code(kind.objectValue, _quote(kind.stringValue))}))';
      }
      return 'Plain(TextType(${max == null ? '' : 'maxLength: $max'}))';
    }
    if (t case InterfaceType(element: final EnumElement e)) {
      final name = e.displayName;
      // What a value added after the code was built reads as (SPEC §25.2).
      final fallbacks = [
        for (final c in e.constants)
          if (_fallback.hasAnnotationOf(c)) c.displayName,
      ];
      if (fallbacks.length > 1) {
        throw InvalidGenerationSourceError(
          '$name: one value at most is its @Fallback, not '
          '${fallbacks.join(', ')}',
          element: e,
        );
      }
      final unknown = fallbacks.isEmpty
          ? ''
          : ', unknown: $name.${fallbacks.single}';
      return 'EnumShape($name.values$unknown)';
    }
    if (t is RecordType) return _recordShape(t, on, where);
    if (t is InterfaceType && t.isDartCoreList) {
      // `@Ref` on a list names its items' kind; its other bounds are
      // the list's.
      final item = _shape(
        t.typeArguments.single,
        on,
        '$where[]',
        bounded: ref != null,
        notes: ref == null ? null : [ref],
      );
      return 'ListShape($item${max == null ? '' : ', maxItems: $max'})';
    }
    if (t is InterfaceType && t.isDartCoreMap) {
      if (!t.typeArguments.first.isDartCoreString) {
        throw InvalidGenerationSourceError(
          '$where: a map is keyed by String',
          element: on,
        );
      }
      final value = _shape(
        t.typeArguments.last,
        on,
        '$where{}',
        bounded: false,
      );
      return 'MapShape($value${max == null ? '' : ', maxEntries: $max'})';
    }
    if (t is InterfaceType && _jsonClass(t.element)) {
      final name = t.element.displayName;
      final helper = '_\$$_c${name}ToJson';
      if (_jsonHelpers.add(helper)) {
        _helpers
          ..writeln()
          ..writeln('Map<String, Object?> $helper($name v) => v.toJson();');
      }
      return 'JsonShape<$name>($name.fromJson, $helper, '
          'type: ${_valueType(t, {})})';
    }
    throw InvalidGenerationSourceError(
      '$where: ${t.getDisplayString()} is no type a word can carry: a bool, '
      'a number, a text, an enum, a list, a map by text, a record of named '
      'fields, or a class with fromJson and toJson (json_serializable, '
      'freezed)',
      element: on,
    );
  }

  /// The shape of record [t], of named fields: a constant made once, named
  /// after its typedef. Its fields say what a parameter would, by the
  /// annotations on them in the typedef ([recordFields]): `@Describe`,
  /// `@FieldName`, `@Default`, bounds. A nullable field may be left out.
  String _recordShape(RecordType t, Element on, String where) {
    if (t.positionalFields.isNotEmpty) {
      throw InvalidGenerationSourceError(
        '$where: a record a word carries has named fields only',
        element: on,
      );
    }
    final alias = t.alias?.element;
    // Unnamed, it is named after where it is, apart from the params'.
    final name =
        alias?.displayName ??
        '$_c${where.split(RegExp('[^A-Za-z0-9]')).map(_pascal).join()}Value';
    final shape = '_\$${name}Shape';
    if (!_recordShapes.add(name)) return shape;
    final type = _dart(t);
    final notesOf = alias == null ? null : recordFields[alias];
    final parts = <String>[];
    final to = <String>[];
    final from = <String>[];
    final at = <String>[];
    // In the order the typedef says them: the analyzer sorts them by name.
    final byName = {for (final f in t.namedFields) f.name: f};
    for (final f in [
      for (final n in notesOf?.keys ?? const <String>[]) ?byName[n],
      for (final f in t.namedFields)
        if (!(notesOf?.containsKey(f.name) ?? false)) f,
    ]) {
      final n = f.name;
      final notes = notesOf?[n] ?? const [];
      DartObject? note(TypeChecker c) => notes
          .where((o) => o.type != null && c.isExactlyType(o.type!))
          .firstOrNull;
      final key = switch (note(_fieldName)) {
        final a? => ConstantReader(a).read('name').stringValue,
        null => n,
      };
      final nullable = f.type.nullabilitySuffix == NullabilitySuffix.question;
      final dflt = switch (note(_default)) {
        final a? => ConstantReader(a).read('value').objectValue,
        null => null,
      };
      final optional = nullable || dflt != null;
      final args = [
        _shape(
          nullable ? _nonNull(f.type) : f.type,
          on,
          '$where.$n',
          notes: notes,
        ),
        if (optional && dflt == null) 'optional: true',
        if (dflt != null) 'defaultValue: ${_constant(dflt, on)}',
        if (_describeOf(note(_describe)) case final d?) 'description: $d',
      ];
      parts.add('${_quote(key)}: Part(${args.join(', ')})');
      to.add('${_quote(key)}: v.$n');
      at.add('v.$n');
      final bare = _dart(f.type).replaceFirst(RegExp(r'\?$'), '');
      from.add(switch ((nullable, dflt)) {
        (_, final DartObject d) =>
          '$n: (m[${_quote(key)}] as $bare?) ?? ${_constant(d, on)}',
        (true, null) when bare == 'Object' => '$n: m[${_quote(key)}]',
        (true, null) => '$n: m[${_quote(key)}] as $bare?',
        (false, null) => '$n: m[${_quote(key)}]! as $bare',
      });
    }
    _helpers
      ..writeln()
      ..writeln(
        'const $shape = RecordShape<$type>({${parts.join(', ')}}, '
        'to: _\$${name}To, from: _\$${name}From, get: _\$${name}At);',
      )
      ..writeln()
      ..writeln(
        'Map<String, Object?> _\$${name}To($type v) => {${to.join(', ')}};',
      )
      ..writeln()
      ..writeln(
        '$type _\$${name}From(Map<String, Object?> m) => (${from.join(', ')});',
      )
      ..writeln()
      ..writeln('Object? _\$${name}At($type v, int i) => ${_byPlace(at)};');
    return shape;
  }

  /// The value type of [t], for a JSON class's fields (SPEC §2): what
  /// json_serializable makes of it. What it cannot tell is any value.
  String _valueType(DartType t, Set<InterfaceElement> seen) {
    if (t.nullabilitySuffix == NullabilitySuffix.question) {
      return 'NullableType(${_valueType(_nonNull(t), seen)})';
    }
    if (t.isDartCoreBool) return 'BoolType()';
    if (t.isDartCoreInt) return 'IntType()';
    if (t.isDartCoreDouble || t.isDartCoreNum) return 'NumType()';
    if (t.isDartCoreString) return 'TextType()';
    if (t is! InterfaceType) return 'AnyType()';
    final e = t.element;
    if (e.displayName == 'DateTime' && e.library.isDartCore) {
      return 'TextType()';
    }
    if (e is EnumElement) {
      return 'EnumType([${[for (final c in e.constants) _quote(c.displayName)].join(', ')}])';
    }
    if (t.isDartCoreList) {
      return 'ListType(${_valueType(t.typeArguments.single, seen)})';
    }
    if (t.isDartCoreMap && t.typeArguments.first.isDartCoreString) {
      return 'MapType(${_valueType(t.typeArguments.last, seen)})';
    }
    if (_jsonClass(e) && seen.add(e)) {
      final fields = [
        for (final (key, type, optional) in _fieldsOf(e as ClassElement))
          '${_quote(key)}: Field(${_valueType(type, {...seen})}'
              '${optional ? ', optional: true' : ''})',
      ];
      return 'ObjectType({${fields.join(', ')}})';
    }
    return 'AnyType()';
  }

  /// A class that serializes itself: a `fromJson` constructor and a
  /// `toJson` method.
  bool _jsonClass(InterfaceElement e) =>
      e is ClassElement &&
      e.getNamedConstructor('fromJson') != null &&
      e.lookUpMethod(name: 'toJson', library: e.library) != null;

  /// Its JSON fields: of the factory freezed redirects, or its own
  /// instance fields (json_serializable); renamed by `@JsonKey(name:)`,
  /// left out by `@JsonKey(includeToJson: false)`; nullable ones may be
  /// absent.
  List<(String, DartType, bool)> _fieldsOf(ClassElement c) {
    final factory = c.constructors
        .where((k) => k.isFactory && k.redirectedConstructor != null)
        .where((k) => k.name == null || k.name == 'new' || k.name!.isEmpty)
        .firstOrNull;
    final out = <(String, DartType, bool)>[];
    void add(Element e, String name, DartType type, {bool optional = false}) {
      final key = _jsonKeyOf(e);
      if (key == null) {
        out.add((
          name,
          type,
          optional || type.nullabilitySuffix == NullabilitySuffix.question,
        ));
      } else if (key case (final String n, true)) {
        out.add((
          n,
          type,
          optional || type.nullabilitySuffix == NullabilitySuffix.question,
        ));
      }
    }

    if (factory != null) {
      for (final p in factory.formalParameters) {
        add(p, p.displayName, p.type);
      }
    } else {
      for (final f in c.fields) {
        if (f.isStatic || !f.isOriginDeclaration || f.isPrivate) continue;
        add(f, f.displayName, f.type);
      }
    }
    return out;
  }

  /// `@JsonKey` of [e], if any: its name, and whether it goes in JSON.
  (String, bool)? _jsonKeyOf(Element e) {
    for (final a in e.metadata.annotations) {
      final v = a.computeConstantValue();
      if (v == null) continue;
      final type = v.type?.element;
      if (type?.displayName != 'JsonKey' ||
          !'${type?.library?.uri}'.startsWith('package:json_annotation/')) {
        continue;
      }
      final r = ConstantReader(v);
      final shown =
          r.peek('includeToJson')?.boolValue != false &&
          r.peek('ignore')?.boolValue != true;
      return (r.peek('name')?.stringValue ?? e.displayName, shown);
    }
    return null;
  }

  String _statesEnum(List<_State> states) {
    final values = [
      for (final s in states)
        "${s.member}<${s.type}>(${_quote(s.name)}, ${s.shape}"
            "${s.keyCode == null ? '' : ', key: ${s.keyCode}'})",
    ];
    return '''
/// The states of [$_c].
enum ${_c}State<T> implements IStateWord<T> {
  ${values.join(',\n  ')};

  const ${_c}State(this.name, this.shape, {this.key});
  @override
  final String name;
  @override
  final Shape<T> shape;
  @override
  final String? key;
}

''';
  }

  String _callablesEnum(String name, String of, List<_Callable> words) {
    final query = of == 'IQueryWord';
    final values = [
      for (final w in words)
        "${w.member}<${w.params}, ${w.returns}>(${_quote(w.name)}, "
            "${w.paramsShape}, ${w.returnsShape ?? 'null'})",
    ];
    return '''
/// The ${query ? 'queries' : 'commands'} of [$_c].
enum $name<P, R> implements $of<P, R> {
  ${values.join(',\n  ')};

  const $name(this.name, this.params, this.returns);
  @override
  final String name;
  @override
  final RecordShape<P> params;
  @override
  final Shape<R>${query ? '' : '?'} returns;
}

''';
  }

  String _factsEnum(List<_Fact> facts) {
    final values = [
      for (final f in facts)
        '${f.member}<${f.type}>(${_quote(f.name)}, ${f.shape})',
    ];
    return '''
/// The facts of [$_c].
enum ${_c}Fact<T> implements IFactWord<T> {
  ${values.join(',\n  ')};

  const ${_c}Fact(this.name, this.shape);
  @override
  final String name;
  @override
  final Shape<T> shape;
}

''';
  }

  DartType _nonNull(DartType t) => cls.library.typeSystem.promoteToNonNull(t);

  DartType _unwrapFuture(DartType t) =>
      t is InterfaceType && (t.isDartAsyncFuture || t.isDartAsyncFutureOr)
      ? t.typeArguments.single
      : t;

  /// [t] as code: a typedef by its name (`ChatLine`, `List<ChatLine>`).
  String _dart(DartType t) {
    final q = t.nullabilitySuffix == NullabilitySuffix.question ? '?' : '';
    String args(List<DartType> ts) =>
        ts.isEmpty ? '' : '<${ts.map(_dart).join(', ')}>';
    if (t.alias case final a?) {
      return '${a.element.displayName}${args(a.typeArguments)}$q';
    }
    if (t is InterfaceType && t.typeArguments.isNotEmpty) {
      return '${t.element.displayName}${args(t.typeArguments)}$q';
    }
    return t.getDisplayString();
  }
}

String _snake(String s) => s
    .replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}')
    .replaceFirst(RegExp('^_'), '');

String _pascal(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// [s] as a Dart string literal of one line.
String _quote(String s) =>
    "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$').replaceAll('\n', r'\n').replaceAll('\r', r'\r')}'";
