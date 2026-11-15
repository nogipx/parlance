/// Checks what an external consumer can import and invoke.
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/error/error.dart';

import 'surface.dart';

Future<void> main() async {
  final root = Directory.current.absolute.path;
  final dir = Directory('$root/.dart_tool').createTempSync('stream_api_');
  var checked = 0;
  final failures = <String>[];
  void check(bool condition, String message) {
    if (!condition) failures.add(message);
    checked++;
  }

  try {
    final fixtures = <String, ({String source, Set<String> missing})>{
      'target_api': (
        source: '''
import 'package:parlance/schema.dart';
void consumer(IParticipant participant, IOwner owner) {
  const target = Principal('module', 'work');
  final address = WordAddress(target, 'notes.add');
  final Principal selected = address.target;
  GeneratedWords(participant: participant, target: selected);
  GeneratedWords.of(owner: owner, target: selected);
  final Future<List<WordTarget>> found = participant.targets();
  final Stream<List<WordTarget>> changes = participant.targetChanges();
  final PublishedWord? publication = null;
  final PublishedVocabulary? vocabulary = null;
  participant.targets(vocabulary: 'notes');
  participant.targetChanges(word: 'notes.add');
}
''',
        missing: {},
      ),
      'generated_vocabulary': (
        source: '''
import 'package:parlance/schema.dart';
import '../../packages/parlance/example/house/words.dart';
const name = HouseVocabulary.name;
const words = HouseVocabulary.words;
const WordSet definition = HouseVocabulary.definition;
void consumer(IParticipant participant, WordTarget target) {
  participant.targets(vocabulary: HouseVocabulary.name);
  participant.targetChanges(word: HouseCommand.setLight.name);
  final PublishedVocabulary vocabulary = target.vocabularies.single;
  final PublishedWord word = vocabulary.words.single;
}
''',
        missing: {},
      ),
      'removed_vocabulary_constant': (
        source: '''
import '../../packages/parlance/example/house/words.dart';
void consumer() { houseWords; }
''',
        missing: {'houseWords'},
      ),
      'removed_discovery_shapes': (
        source: '''
import 'package:parlance/schema.dart';
void consumer(IParticipant participant, WordSet vocabulary, IWord word, WordTarget target) {
  participant.targets(vocabulary: vocabulary);
  participant.targetChanges(word: word);
  target.words;
}
''',
        missing: {'vocabulary', 'word', 'words'},
      ),
      'removed_addressing_names': (
        source: '''
import 'package:parlance/schema.dart';
void consumer(IParticipant participant, WordAddress address) {
  participant.providers();
  participant.providerChanges();
  address.provider;
  WordProvider? first;
  ProvidedWord? word;
  ProviderDiscovery? discovery;
}
''',
        missing: {
          'providers',
          'providerChanges',
          'provider',
          'WordProvider',
          'ProvidedWord',
          'ProviderDiscovery',
        },
      ),
      'host_access': (
        source: '''
import 'package:parlance/app.dart';
import 'package:parlance/tools.dart';
void consumer(Host host) {
  final address = WordAddress(const Principal('module', 'work'), 'notes.add');
  host.setAccess(address: address, access: const WordAccess(callers: Callers.anyone));
  host.clearAccess(address: address);
  host.registry.accessWarnings.listen((AccessWarning event) {
    event.word;
    event.operation;
  });
}
''',
        missing: {},
      ),
      'participant_cannot_administer_access': (
        source: '''
import 'package:parlance/app.dart';
import 'package:parlance/tools.dart';
void consumer(IParticipant participant, Host host) {
  participant.setAccess();
  participant.clearAccess();
  host.registry.setWordAccess();
}
''',
        missing: {'setAccess', 'clearAccess', 'setWordAccess'},
      ),
      'schema': (
        source: '''
import 'package:parlance/schema.dart';
void consumer() {
  const StreamFailure(StreamFailureCode.cancelled, 'cancelled');
  StreamLimits();
}
''',
        missing: {'StreamLimits'},
      ),
      'app': (
        source: '''
import 'package:parlance/app.dart';
void consumer() {
  Host(limits: HostLimits(streams: StreamLimits(bufferItems: 8)));
}
''',
        missing: {},
      ),
      'wire_helpers': (
        source: '''
import 'package:parlance/schema.dart';
import 'package:parlance/app.dart';
import 'package:parlance/tools.dart';
import 'package:parlance/testing.dart';
void consumer(StreamLimits limits) {
  streamLimitsToJson(limits);
  streamLimitsFromJson({});
  receiveExchange;
  exchangeRequests;
  encodeDataStream;
  decodeDataStream;
  boundedStream;
  StreamLease;
  LazyDataStream;
}
''',
        missing: {
          'streamLimitsToJson',
          'streamLimitsFromJson',
          'receiveExchange',
          'exchangeRequests',
          'encodeDataStream',
          'decodeDataStream',
          'boundedStream',
          'StreamLease',
          'LazyDataStream',
        },
      ),
      'registry': (
        source: '''
import 'package:parlance/app.dart';
import 'package:parlance/tools.dart';
void consumer(Host host) {
  host.registry.defineStream;
  host.registry.openStream;
  host.registry.endTargetStreams;
}
''',
        missing: {'defineStream', 'openStream', 'endTargetStreams'},
      ),
      'observations': (
        source: '''
import 'package:parlance/app.dart';
import 'package:parlance/tools.dart';
void consumer(Host host) {
  final List<StreamSnapshot> active = host.registry.activeStreams;
  final Stream<StreamEvent> events = host.registry.streamEvents;
  active.single.output.pendingItems;
  events.listen((event) => event.stream.termination);
}
''',
        missing: {},
      ),
      'read_only_observations': (
        source: '''
import 'package:parlance/app.dart';
import 'package:parlance/tools.dart';
void consumer(Host host) {
  host.registry.activeStreams.single.cancel();
  host.registry.activeStreams.single.output.pendingItems = 42;
}
''',
        missing: {'cancel', 'pendingItems'},
      ),
      'participant': (
        source: '''
import 'package:parlance/app.dart';
import 'package:parlance/tools.dart';
void consumer(IParticipant participant) {
  participant.raw.defineStream(ServerStreamDescriptor('sensor.values',
    type: const IntType()), (_) => const Stream<int>.empty());
}
''',
        missing: {},
      ),
      'limits': (
        source: '''
import 'package:parlance/app.dart';
void consumer(StreamLimits limits) {
  limits.toJson();
  limits.restrict(StreamLimits.unbounded);
  StreamLimits.fromJson({});
}
''',
        missing: {'toJson', 'restrict', 'fromJson'},
      ),
    };
    for (final e in fixtures.entries) {
      File('${dir.path}/${e.key}.dart').writeAsStringSync(e.value.source);
    }
    final collection = AnalysisContextCollection(
      includedPaths: [dir.path, '$root/packages/parlance/lib'],
    );
    Future<Set<String>> exportsOf(String relative) async {
      final file = '$root/packages/parlance/lib/$relative';
      final result = await collection
          .contextFor(file)
          .currentSession
          .getResolvedLibrary(file);
      if (result is! ResolvedLibraryResult) {
        throw StateError('cannot resolve $file');
      }
      return result.element.exportNamespace.definedNames2.keys.toSet();
    }

    final streamNames = {
      ...await exportsOf('src/remote/data_streams.dart'),
      ...await exportsOf('src/registry/streams.dart'),
    };
    // Enumerate the internal libraries so newly added helpers are checked too.
    for (final library in [
      'schema.dart',
      'app.dart',
      'tools.dart',
      'testing.dart',
    ]) {
      final public = await exportsOf(library);
      final allowed = {
        if (library != 'testing.dart') ...[
          'StreamFailure',
          'StreamFailureCode',
        ],
        if (library == 'app.dart' || library == 'tools.dart') 'StreamLimits',
      };
      for (final name in streamNames.difference(allowed)) {
        check(
          !public.contains(name),
          '$library exports internal stream helper $name',
        );
      }
    }
    for (final e in fixtures.entries) {
      final file = '${dir.path}/${e.key}.dart';
      final result = await collection
          .contextFor(file)
          .currentSession
          .getResolvedUnit(file);
      if (result is! ResolvedUnitResult) {
        throw StateError('cannot resolve $file');
      }
      final errors = result.diagnostics
          .where((d) => d.diagnosticCode.severity == DiagnosticSeverity.ERROR)
          .toList();
      for (final name in e.value.missing) {
        check(
          errors.any(
            (d) => e.value.source
                .substring(d.offset, d.offset + d.length)
                .contains(name),
          ),
          '${e.key}: $name is unexpectedly accessible',
        );
      }
      check(
        errors.length == e.value.missing.length,
        '${e.key}: unexpected diagnostics: $errors',
      );
    }
    final surface = await surfaceOf('$root/packages/parlance', collection);
    for (final library in frozen) {
      final names = surface
          .where((i) => i.library == library && i.member == null)
          .map((i) => i.name)
          .toSet();
      for (final name in [
        'StreamCall',
        'StreamHandler',
        'StreamLease',
        'LazyDataStream',
        'RegistryStreams',
        'IRawParticipant',
        'boundedStream',
        'WireJson',
        'RpcContext',
        'streamLimitsToJson',
        'streamLimitsFromJson',
        'StreamSnapshot',
        'StreamTraffic',
        'StreamEvent',
        'StreamEventKind',
        'StreamTermination',
      ]) {
        check(!names.contains(name), '$library exports $name');
      }
    }
    final limits = surface
        .where((i) => i.name == 'StreamLimits')
        .map((i) => i.member)
        .toSet();
    for (final member in ['toJson', 'restrict', 'fromJson']) {
      check(!limits.contains(member), 'StreamLimits.$member is frozen');
    }
    if (failures.isNotEmpty) throw StateError(failures.join('\n'));
    stdout.writeln('public stream API: $checked checks passed');
  } finally {
    dir.deleteSync(recursive: true);
  }
}
