import 'dart:async';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/scope.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:dart_style/dart_style.dart';
import 'package:parlance/tools.dart'
    show isValidName, isValidVocabularyName, checkWordName;
import 'package:parlance/schema.dart' hide RecordType;
import 'package:pub_semver/pub_semver.dart' show Version;
import 'package:source_gen/source_gen.dart';

/// What a name is (SPEC §1), as the generator tells it.
const _nameRule =
    'one word, from a letter, of lower-case letters, digits, _ and - '
    '(door_left_open), no .; a version is version: 2, not in the name';

const _state = TypeChecker.typeNamed(StateWord, inPackage: 'parlance');
const _command = TypeChecker.typeNamed(CommandWord, inPackage: 'parlance');
const _query = TypeChecker.typeNamed(QueryWord, inPackage: 'parlance');
const _fact = TypeChecker.typeNamed(FactWord, inPackage: 'parlance');
const _range = TypeChecker.typeNamed(Range, inPackage: 'parlance');
const _length = TypeChecker.typeNamed(Length, inPackage: 'parlance');
const _ref = TypeChecker.typeNamed(ChoiceOf, inPackage: 'parlance');
const _describe = TypeChecker.typeNamed(Describe, inPackage: 'parlance');
const _fieldName = TypeChecker.typeNamed(FieldName, inPackage: 'parlance');
const _default = TypeChecker.typeNamed(Default, inPackage: 'parlance');
const _longest = TypeChecker.typeNamed(Longest, inPackage: 'parlance');
const _fallback = TypeChecker.typeNamed(Fallback, inPackage: 'parlance');

/// Makes the typed words (SPEC §18, §23) of a class marked `@Vocabulary`:
/// an enum per kind of word it has, a record and its shape per params or
/// payload, and the vocabulary of them all (a `WordSet`).
final class VocabularyGenerator extends GeneratorForAnnotation<Vocabulary> {
  const VocabularyGenerator();

  /// Each vocabulary of the library: one library may say several (an index
  /// of parts, `part 'rooms.dart'`), so what they share (a record's shape,
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
    if (!isValidVocabularyName(vocabulary)) {
      throw InvalidGenerationSourceError(
        '@Vocabulary: "$vocabulary" is no name of a vocabulary: $_nameRule',
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

  /// The kinds of choices its words speak of (a keyed state's keys, what
  /// a `@ChoiceOf` names), and where they first name each, in order.
  final Map<String, Element> _kindsNamed = {};

  /// [kind], named by [on] as a key or a ref.
  void _named(String kind, Element on) =>
      _kindsNamed.putIfAbsent(kind, () => on);

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
              r.peek('keyOf')?.stringValue,
            )
            ..keyCode = switch (r.peek('keyOf')) {
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
        _meta(f, r);
        named(f);
        facts.add(f);
      } else if (m.isAbstract) {
        _unmarked(m);
      }
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
    for (final s in states) {
      if (s.key case final k?) _named(k, s.element);
    }
    _checkKinds();
    if (_kindsNamed.isNotEmpty) out.write(_kindsOf());
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
      ..writeln('], from: ${_quote(from)}, dartName: ${_quote(_words)});')
      ..write(_helpers);
    return out.toString();
  }

  Never _unmarked(Element e) => throw InvalidGenerationSourceError(
    '${e.displayName} is abstract but no word: mark it @StateWord, '
    '@CommandWord, @QueryWord or @FactWord',
    element: e,
  );

  String _name(Element e, ConstantReader r) {
    final own = r.peek('name')!.stringValue;
    // One word: the vocabulary's and the version's are the only dots.
    if (own.isNotEmpty && !RegExp(r'^[a-z][a-z0-9_-]*$').hasMatch(own)) {
      throw InvalidGenerationSourceError(
        '${e.displayName}: "$own" is no name of a word: $_nameRule',
        element: e,
      );
    }
    // `v2` would read as the vocabulary's own word, its version 2.
    if (RegExp(r'^v[0-9]+$').hasMatch(own)) {
      throw InvalidGenerationSourceError(
        '${e.displayName}: "$own" reads as a version: a version is '
        'version: ${own.substring(1)}, a name is a word',
        element: e,
      );
    }
    final version = r.peek('version')?.intValue;
    if (version != null && version < 2) {
      throw InvalidGenerationSourceError(
        '${e.displayName}: version $version: a version past the first is 2 '
        'or more; the first has none',
        element: e,
      );
    }
    // '' is the vocabulary itself: `signal`, beside `signal.raise`.
    final base = own.isEmpty ? vocabulary : '$vocabulary.$own';
    final name = version == null ? base : '$base.v$version';
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
      final us = _micros(o);
      w.options.add('deadline: const Duration(microseconds: $us)');
    }
    w.available = r.peek('whyNot')?.boolValue ?? false;
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
    if (t != null && t.isDartCoreDouble) {
      final d = o.toDoubleValue()!;
      if (!d.isFinite) {
        throw InvalidGenerationSourceError(
          'meta holds JSON: a number in it is finite, not $d',
          element: at,
        );
      }
      return '$d';
    }
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
      final InterfaceElement e => switch (_nameOf(e)) {
        final r? => '$r.${v.displayName}',
        null => literal,
      },
      LibraryElement() => _nameOf(v) ?? literal,
      _ => literal,
    };
  }

  /// [e]'s name as the generated part says it: alone when the library has
  /// it or imports it with no prefix, after the prefix it is imported by
  /// otherwise (`who.crew`); null when the part does not see it.
  String? _nameOf(Element e) {
    final name = e.displayName;
    bool found(Scope scope) => switch (scope.lookup(name).getter) {
      final GetterElement g => g.variable == e,
      final x => x == e,
    };
    final library = cls.library.firstFragment;
    if (found(library.scope)) return name;
    for (final p in library.prefixes) {
      if (found(p.scope)) return '${p.displayName}.$name';
    }
    return null;
  }

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

  /// `I<Class>Client` (SPEC §23.5): the words as a consumer uses them,
  /// over a participant, here or across a connection: states read and
  /// watched, commands and queries as methods of the class's params that
  /// answer or throw [CallNotDone], facts as streams of their payloads.
  /// Made by its factories, `I<Class>Client(participant)` and
  /// `I<Class>Client.of(owner)`, over a class of the library's own, so
  /// what uses it names the interface alone and a test stands in.
  String _clientOf(
    List<_State> states,
    List<_Callable> commands,
    List<_Callable> queries,
    List<_Fact> facts,
  ) {
    final members = <String, Element>{};
    void member(String name, _Word w) {
      if (const {
            'of',
            'status',
            'statusChanges',
            'mismatches',
          }.contains(name) ||
          members.containsKey(name)) {
        throw InvalidGenerationSourceError(
          '$name is had twice by I${_c}Client: name ${w.member} otherwise, or '
          '@Vocabulary(client: false)',
          element: w.element,
        );
      }
      members[name] = w.element;
    }

    // Each member once: what it says, its signature, and its body in the
    // client over a participant. The interface says Dart's types, the
    // vocabulary's own and a word's status; a fact's message (for an owner
    // to follow from) is the client's alone.
    final all = <({List<String> docs, String signature, String body})>[];
    final own = <({List<String> docs, String signature, String body})>[];
    // Whether a word is there, in the interface too: a part that takes it
    // asks before it calls.
    final status = <({List<String> docs, String signature, String body})>[
      (
        docs: [
          'Whether [word] is there for the participant now, as this code was built',
          'against it: `WordMismatch`, saying where, when not (SPEC §6.5).',
        ],
        signature: 'WordStatus status(IWord word)',
        body: '=> _\$words.status(word);',
      ),
      (
        docs: ['[status], then whenever it changes.'],
        signature: 'Stream<WordStatus> statusChanges(IWord word)',
        body: '=> _\$words.statusChanges(word);',
      ),
      (
        docs: [
          'Each word of [$_c] there but not as this code was built against,',
          'with where it breaks; empty when all keep their promises. For a',
          'start in development: `assert(client.mismatches.isEmpty)`.',
        ],
        signature: 'Map<String, List<WordBreak>> get mismatches',
        body: '=> _\$words.mismatches($_words.words);',
      ),
    ];
    for (final st in states) {
      final word = '${_c}State.${st.member}';
      member(st.member, st);
      all.add(
        st.key == null
            ? (
                docs: ['${st.name}: its value now, and its changes.'],
                signature: 'IStateOf<${st.type}> get ${st.member}',
                body: '=> _\$words.stateOf($word);',
              )
            : (
                docs: [
                  '${st.name}, by ${st.key}: each value, and its changes.',
                ],
                signature: 'IKeyedOf<${st.type}> get ${st.member}',
                body: '=> _\$words.keyedOf($word);',
              ),
      );
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
              '    final r = await _\$words.$how($_c$kind.${c.member}).$act($record);\n'
              '    if (r case CallDone(:final value)) return value;\n'
              '    throw CallNotDone(r);\n'
              '  }',
        ));
      }
    }
    for (final f in facts) {
      member(f.member, f);
      all.add((
        docs: ['${f.name}: what it says from now on, and its messages.'],
        signature: 'IFactOf<${f.type}> get ${f.member}',
        body: '=> _\$words.factOf(${_c}Fact.${f.member});',
      ));
    }

    all.addAll(status);
    final out = StringBuffer()
      ..writeln('/// The words of [$_c] as a consumer uses them: what a part')
      ..writeln('/// that uses them takes, so a stand-in can be given in its')
      ..writeln('/// place.')
      ..writeln('abstract interface class I${_c}Client {')
      ..writeln(
        '  /// The words through [participant], here or across a connection:',
      )
      ..writeln('  /// what `main` gives a part that uses them.')
      ..writeln(
        '  factory I${_c}Client(IParticipant participant) = _\$${_c}Client;',
      )
      ..writeln()
      ..writeln(
        '  /// The words through the participant [owner] is attached to,',
      )
      ..writeln(
        '  /// for an owner that uses them: made in its constructor, its',
      )
      ..writeln('  /// streams heard (`hear`, `listen`) once it is attached.')
      ..writeln('  factory I${_c}Client.of(IOwner owner) = _\$${_c}Client._of;')
      ..writeln();
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
      ..writeln('/// The words of [$_c] through a participant, here or across')
      ..writeln('/// a connection. Made, it tells the registry the code was')
      ..writeln('/// built against them, for it to say where one is defined')
      ..writeln('/// otherwise (SPEC §6.9).')
      ..writeln('final class _\$${_c}Client implements I${_c}Client {')
      ..writeln('  _\$${_c}Client(IParticipant participant)')
      ..writeln('    : _\$words = GeneratedWords(participant) {')
      ..writeln('    _\$words.builtAgainst($_words.words, from: $_words.from);')
      ..writeln('  }')
      ..writeln()
      ..writeln('  _\$${_c}Client._of(IOwner owner)')
      ..writeln('    : _\$words = GeneratedWords.of(owner) {')
      ..writeln('    _\$words.builtAgainst($_words.words, from: $_words.from);')
      ..writeln('  }')
      ..writeln()
      ..writeln('  final GeneratedWords _\$words;');
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

  /// Every kind its words name is a name of one word.
  void _checkKinds() {
    for (final MapEntry(key: k, value: on) in _kindsNamed.entries) {
      if (isValidName(k) && !k.contains('.')) continue;
      throw InvalidGenerationSourceError(
        '${on.displayName}: choices "$k" is no name: one word, $_nameRule',
        element: on,
      );
    }
  }

  /// `<Class>Choices`: a constant of each name of choices its words name,
  /// for the owner that gives them.
  String _kindsOf() {
    final kinds = [..._kindsNamed.keys];
    final out = StringBuffer()
      ..writeln(
        '/// The kinds of choices [$_c] speaks of: what an owner gives by',
      )
      ..writeln('/// `choices(${_c}Choices.${_keyParam(kinds.first)}, ...)`.')
      ..writeln('abstract final class ${_c}Choices {');
    for (final k in kinds) {
      out.writeln('  static const String ${_keyParam(k)} = ${_quote(k)};');
    }
    out
      ..writeln('}')
      ..writeln();
    return out.toString();
  }

  /// The names an owner base has besides its words: what every Dart
  /// object has.
  static const _ownerMembers = {
    'hashCode',
    'runtimeType',
    'toString',
    'noSuchMethod',
  };

  /// `<Class>OwnerBase` (SPEC §23.4): an owner base that defines every word
  /// and keeps what the owner set of each state, writing it; says each
  /// fact by a method of its params; and serves each command and query by
  /// a handler of its params, for the owner to write. Nothing of it asks
  /// the owner for a cause: what a handler does follows from its call.
  String _ownerBase(
    List<_State> states,
    List<_Callable> commands,
    List<_Callable> queries,
    List<_Fact> facts,
  ) {
    final factClasses = StringBuffer();
    for (final w in [...states, ...commands, ...queries, ...facts]) {
      if (_ownerMembers.contains(w.member)) {
        throw InvalidGenerationSourceError(
          '${w.member} is a name every owner base has: name it otherwise, or '
          '@Vocabulary(owner: false)',
          element: w.element,
        );
      }
    }
    // Each name the base gives the owner, once.
    final had = <String, _Word>{};
    void member(String name, _Word w) {
      if (had[name] case final other?) {
        throw InvalidGenerationSourceError(
          '$name is had twice by ${_c}OwnerBase: name ${w.member} or '
          '${other.member} otherwise, or @Vocabulary(owner: false)',
          element: w.element,
        );
      }
      had[name] = w;
    }

    String opts(_Word w) => [
      ...w.options,
      if (w.available) 'whyNot: whyNot${_pascal(w.member)}',
    ].join(', ');
    String args(_Callable c, String of) => [
      for (final p in (c.element as MethodElement).formalParameters)
        '${p.displayName}: $of.${p.displayName}',
    ].join(', ');

    final out = StringBuffer()
      ..writeln(
        '/// The owner base of [$_c]: it defines every word, keeps what',
      )
      ..writeln('/// the owner set of each state and writes it, says each fact')
      ..writeln('/// by a method of its params, and serves each command and')
      ..writeln('/// query by a handler of its params. What a handler writes,')
      ..writeln('/// says and calls follows from the call it serves.')
      ..writeln('abstract class ${_c}OwnerBase implements IOwner {')
      ..writeln('  ${_c}OwnerBase() {')
      ..writeln(
        '    IOwner.made(this, define: _\$define, write: _\$write, '
        'vocabulary: $_words);',
      )
      ..writeln('  }')
      ..writeln();
    for (final st in states) {
      final m = st.member;
      final t = st.type;
      if (st.key case final kind?) {
        member(m, st);
        out
          ..writeln('  /// ${st.name}, by $kind: what this owner set of each,')
          ..writeln('  /// read by `of`, written by `set` and `remove`.')
          ..writeln('  final Keyed<$t> $m = Keyed<$t>();')
          ..writeln();
      } else {
        member(m, st);
        out
          ..writeln(
            '  /// ${st.name}: what this owner set last, read by `value`,',
          )
          ..writeln('  /// written by `set` and `remove`.')
          ..writeln('  final Single<$t> $m = Single<$t>();')
          ..writeln();
      }
    }
    for (final f in facts) {
      member(f.member, f);
      out.writeln('  IFactSayerOf<${f.type}>? _\$${f.member};');
    }
    if (facts.isNotEmpty) {
      out
        ..writeln()
        ..writeln(
          '  void _\$say<T>(String fact, IFactSayerOf<T>? e, T payload, '
          'Principal? by) {',
        )
        ..writeln('    if (e == null) {')
        ..writeln('      IOwner.said(this, fact, payload);')
        ..writeln('    } else {')
        ..writeln('      e.say(payload, by: by);')
        ..writeln('    }')
        ..writeln('  }');
    }
    out
      ..writeln()
      ..writeln('  void _\$define(IParticipant participant) {');
    // A vocabulary of no words (an owner of rules alone) defines none.
    if (states.isNotEmpty ||
        facts.isNotEmpty ||
        commands.isNotEmpty ||
        queries.isNotEmpty) {
      out.writeln('    final p = GeneratedWords(participant);');
    }
    for (final st in states) {
      final define = 'p.state(${_c}State.${st.member}).define(${opts(st)})';
      out.writeln(
        st.key == null
            ? '    Single.attach(${st.member}, $define);'
            : '    Keyed.attach(${st.member}, $define);',
      );
    }
    for (final f in facts) {
      out.writeln(
        '    _\$${f.member} = p.fact(${_c}Fact.${f.member})'
        '.define(${opts(f)});',
      );
    }
    // Served by the params alone: the generated code holds no call.
    String serving(_Callable c) =>
        (c.element as MethodElement).formalParameters.isEmpty
        ? '(_) => ${c.member}()'
        : '(x) => ${c.member}(${args(c, 'x')})';
    for (final c in commands) {
      out.writeln(
        '    p.command(${_c}Command.${c.member})'
        '.serve(${[serving(c), opts(c)].where((x) => x.isNotEmpty).join(', ')});',
      );
    }
    for (final q in queries) {
      out.writeln(
        '    p.query(${_c}Query.${q.member})'
        '.serve(${[serving(q), opts(q)].where((x) => x.isNotEmpty).join(', ')});',
      );
    }
    out
      ..writeln('  }')
      ..writeln()
      ..writeln('  /// What it set before it was attached, written once it is.')
      ..writeln('  var _\$written = false;')
      ..writeln('  void _\$write() {')
      ..writeln('    if (_\$written) return;')
      ..writeln('    _\$written = true;');
    for (final st in states) {
      final m = st.member;
      if (st.key != null) {
        out.writeln('    Keyed.writeAll($m);');
      } else {
        out.writeln('    Single.write($m);');
      }
    }
    out
      ..writeln('  }')
      ..writeln();
    for (final f in facts) {
      final ps = (f.element as MethodElement).formalParameters;
      if (ps.any((p) => p.displayName == 'by')) {
        throw InvalidGenerationSourceError(
          '${f.member}: a fact\'s param is not named by, its owner base '
          'says one',
          element: f.element,
        );
      }
      final positional = ps.length == 1 && ps.single.isPositional;
      final signature = positional
          ? '${_dart(ps.single.type)} ${ps.single.displayName}, '
                '{Principal? by}'
          : '{${[for (final p in ps) _param(p), 'Principal? by'].join(', ')}}';
      final payload = positional ? ps.single.displayName : _recordOf(ps);
      // A fact is an object of the base, as a state is: said by `say`, its
      // params the payload's.
      final type = '$_c${_pascal(f.member)}Fact';
      out
        ..writeln('  /// ${f.name}: said by `say`.')
        ..writeln('  late final $type ${f.member} = $type._(this);')
        ..writeln();
      factClasses
        ..writeln('/// ${f.name}, as [${_c}OwnerBase] says it.')
        ..writeln('final class $type {')
        ..writeln('  $type._(this._base);')
        ..writeln('  final ${_c}OwnerBase _base;')
        ..writeln()
        ..writeln('  /// Says ${f.name}; on behalf of [by], when given.')
        ..writeln(
          "  void say($signature) => _base._\$say(${_quote(f.name)}, "
          "_base._\$${f.member}, $payload, by);",
        )
        ..writeln('}')
        ..writeln();
    }
    for (final c in commands) {
      member(c.member, c);
      final ps = (c.element as MethodElement).formalParameters;
      final signature = ps.isEmpty ? '' : '{${ps.map(_param).join(', ')}}';
      out
        ..writeln()
        ..writeln('  /// Serves ${c.name}.')
        ..writeln('  ${c.declared} ${c.member}($signature);');
      if (c.available) {
        member('whyNot${_pascal(c.member)}', c);
        out
          ..writeln()
          ..writeln('  /// Why ${c.name} cannot run now; null when it can.')
          ..writeln('  String? whyNot${_pascal(c.member)}();');
      }
    }
    for (final q in queries) {
      member(q.member, q);
      final ps = (q.element as MethodElement).formalParameters;
      final signature = ps.isEmpty ? '' : '{${ps.map(_param).join(', ')}}';
      out
        ..writeln()
        ..writeln('  /// Answers ${q.name}.')
        ..writeln('  ${q.declared} ${q.member}($signature);');
      if (q.available) {
        member('whyNot${_pascal(q.member)}', q);
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
      ..writeln()
      ..write(factClasses);
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
    if (v.toDoubleValue() case final d?) {
      if (!d.isFinite) {
        throw InvalidGenerationSourceError(
          '${p.displayName}: a default is a finite number, not $d',
          element: p,
        );
      }
      return '$d';
    }
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
    if (t is InvalidType) {
      throw InvalidGenerationSourceError(
        '$where: its type does not resolve here: an import missing, or a '
        'name misspelt',
        element: on,
      );
    }
    // Any value, null too.
    if (t is DynamicType || (t is InterfaceType && t.isDartCoreObject)) {
      return 'PlainShape(AnyType())';
    }
    if (t.nullabilitySuffix == NullabilitySuffix.question) {
      final inner = _nonNull(t);
      return 'NullableShape<${_dart(inner)}>('
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
    final longest = note(_longest);
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

    if (t.isDartCoreBool) return 'PlainShape(BoolType())';
    if (t is InterfaceType &&
        t.element.name == 'DateTime' &&
        t.element.library.isDartCore) {
      return 'DateTimeShape()';
    }
    if (t is InterfaceType &&
        t.element.name == 'Duration' &&
        t.element.library.isDartCore) {
      if (longest == null) return 'DurationShape()';
      final us = _micros(ConstantReader(longest).read('max').objectValue);
      return 'DurationShape(max: Duration(microseconds: $us))';
    }
    if (longest != null) {
      throw InvalidGenerationSourceError(
        '$where: @Longest bounds a Duration',
        element: on,
      );
    }
    if (t.isDartCoreInt) return 'PlainShape(${bounds('IntType')})';
    if (t.isDartCoreDouble) {
      throw InvalidGenerationSourceError(
        '$where: a number a word carries is num or int, not double (JSON '
        'does not keep 1.0 apart from 1)',
        element: on,
      );
    }
    if (t.isDartCoreNum) return 'PlainShape(${bounds('NumType')})';
    if (t.isDartCoreString) {
      if (ref != null) {
        final kind = ConstantReader(ref).read('of');
        _named(kind.stringValue, on);
        return 'PlainShape(ChoiceType(${_code(kind.objectValue, _quote(kind.stringValue))}))';
      }
      return 'PlainShape(TextType(${max == null ? '' : 'maxLength: $max'}))';
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
      final named = _nameOf(e) ?? name;
      final unknown = fallbacks.isEmpty
          ? ''
          : ', unknown: $named.${fallbacks.single}';
      return 'EnumShape($named.values$unknown)';
    }
    if (t is RecordType) return _recordShape(t, on, where);
    if (t is InterfaceType && t.isDartCoreList) {
      // `@ChoiceOf` on a list names its items' kind; its other bounds are
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
      final named = _nameOf(t.element) ?? name;
      // By the name as said here: two classes of one name, by two
      // prefixes, have each its own.
      final helper = '_\$$_c${named.replaceAll('.', r'$')}ToJson';
      if (_jsonHelpers.add(helper)) {
        _helpers
          ..writeln()
          ..writeln('Map<String, Object?> $helper($named v) => v.toJson();');
      }
      return 'JsonShape<$named>(from: $named.fromJson, to: $helper, '
          'type: ${_valueType(t, {})})';
    }
    throw InvalidGenerationSourceError(
      '$where: ${t.getDisplayString()} is no type a word can carry: a bool, '
      'a number, a text, a Duration, a DateTime, an enum, a list, a map by text, a '
      'record of named fields, or a class with fromJson and toJson '
      '(json_serializable, freezed)',
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
      return 'RecordType({${fields.join(', ')}})';
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
      return '${_nameOf(a.element) ?? a.element.displayName}'
          '${args(a.typeArguments)}$q';
    }
    if (t is InterfaceType) {
      return '${_nameOf(t.element) ?? t.element.displayName}'
          '${args(t.typeArguments)}$q';
    }
    return t.getDisplayString();
  }
}

String _pascal(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// [s] as a Dart string literal of one line.
String _quote(String s) =>
    "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$').replaceAll('\n', r'\n').replaceAll('\r', r'\r')}'";

/// The microseconds of a constant `Duration`: its field, as each SDK's
/// analyzer gives it (`_duration`; `inMicroseconds` on some).
int _micros(DartObject d) =>
    (d.getField('_duration') ?? d.getField('inMicroseconds'))?.toIntValue() ??
    (throw StateError('a Duration the analyzer gives no microseconds of'));
