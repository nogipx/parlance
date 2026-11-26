import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import 'package:flutter/rendering.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parlance_console/main.dart';
import 'package:parlance_console/src/viewer.dart';
import 'package:parlance_console/src/look.dart';
import 'package:parlance/app.dart' show Host;
import 'package:parlance/tools.dart';

const studio = Principal('studio');
const viewer = Principal('viewer', 'twitch.7');
const basics = Principal('plugin', 'basics');

/// A journal of two chat lines: each a call that says a fact, a plugin's
/// call in answer that writes, and one it may not make.
Future<String> journalLines() async {
  final host = Host();
  final r = host.registry;
  final lines = <String>[];
  final sub = r.journal.listen((e) => lines.add(jsonEncode(e.toJson())));
  final p = host
      .participant(
        studio,
        vocabularies: [const WordSet.open('chat'), const WordSet.open('clip')],
      )
      .raw;
  final line = p.defineFact(
    FactDescriptor('studio/chat.line', type: const TextType()),
  );
  final last = p.defineState(
    StateDescriptor('studio/clip.last', type: const TextType()),
  );
  p.defineCommand(
    CommandDescriptor('studio/chat.say', callers: Callers.only(['viewer'])),
    (c) => line.say('!clip', cause: c.causeFor(studio)),
  );
  var n = 0;
  p.defineCommand(
    CommandDescriptor('studio/clip.save', callers: Callers.only(['plugin'])),
    (c) => last.set('clip-${++n}', cause: c.causeFor(studio)),
  );
  p.defineCommand(
    CommandDescriptor('studio/clip.cover', callers: Callers.only(['user'])),
    (_) {},
  );
  final plugin = host.participant(basics).raw;
  plugin.facts('studio/chat.line').listen((f) async {
    await plugin.call(
      'studio/clip.save',
      {},
      cause: Cause(basics, parent: f.id),
    );
    await plugin.call(
      'studio/clip.cover',
      {},
      cause: Cause(basics, parent: f.id),
    );
  });
  for (final id in ['irc:1', 'irc:2']) {
    await host.participant(viewer).raw.call('studio/chat.say', {}, id: id);
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  await sub.cancel();
  await host.dispose();
  return '${lines.join('\n')}\n';
}

String diagnosticLines() {
  final at = DateTime.utc(2026, 11, 15, 12);
  final cause = const Cause(
    Principal('user'),
    unresolvedParent: 'unavailable-parent',
  );
  final entries = <JournalEntry>[
    JournalDiagnostic(
      id: 'catalog',
      word: 'house/house.state',
      cause: const Cause(Principal.system),
      at: at,
      event: 'word.defined',
      epoch: 'one',
      n: 1,
    ),
    JournalStart(
      CallStarted(
        id: 'root',
        command: 'house/house.run',
        params: {},
        cause: cause,
        started: at,
      ),
      epoch: 'one',
      n: 2,
      payloads: false,
    ),
    JournalDiagnostic(
      id: 'decision',
      word: 'house/house.run',
      cause: cause.child('root', word: 'house/house.run'),
      at: at,
      event: 'access.allowed',
      data: {'operation': 'root', 'source': 'host'},
      epoch: 'one',
      n: 3,
    ),
    JournalWrite(
      StateChange(
        seq: 1,
        id: 'first-write',
        state: 'house/house.state',
        key: null,
        value: null,
        previous: null,
        removed: false,
        cause: cause.child('root', word: 'house/house.run'),
        at: at,
      ),
      epoch: 'one',
      n: 4,
      payloads: false,
    ),
    JournalEnd(
      CallRecord(
        id: 'root',
        command: 'house/house.run',
        params: {},
        cause: cause,
        result: const CallDone(null),
        started: at,
        finished: at.add(const Duration(seconds: 2)),
        late: true,
        replyResult: const CallTimedOut(),
        repliedAt: at.add(const Duration(seconds: 1)),
      ),
      epoch: 'one',
      n: 5,
      payloads: false,
    ),
    JournalWrite(
      StateChange(
        seq: 2,
        id: 'second-write',
        state: 'house/house.state',
        key: null,
        value: null,
        previous: null,
        removed: false,
        cause: const Cause(Principal('house')),
        at: at.add(const Duration(seconds: 3)),
      ),
      epoch: 'one',
      n: 7,
      payloads: false,
    ),
  ];
  return entries.map((e) => jsonEncode(e.toJson())).join('\n');
}

void main() {
  test('live pages keep the selected conversation and message', () async {
    final lines = const LineSplitter().convert(await journalLines());
    final middle = lines.indexWhere((s) => s.contains('irc:2'));
    expect(middle, greaterThan(0));
    final model = Viewer()..appendLive(lines.take(middle).toList());
    addTearDown(model.dispose);
    model.select(model.all.firstWhere((c) => c.id == 'viewer/twitch.7#irc:1'));
    model.choose(model.tree.first);
    final id = model.node!.id;
    model.appendLive(lines.skip(middle).toList());
    expect(model.selected?.id, 'viewer/twitch.7#irc:1');
    expect(model.node?.id, id);
    expect(model.all.any((c) => c.id == 'viewer/twitch.7#irc:2'), true);
  });

  test('colouring retains the full line and distinguishes severity and span outcome', () {
    for (final (body, color) in [
      ('WARNING sync  retry', Look.refused),
      ('ERROR sync  stopped', Look.failed),
      ('SPAN  engine  sync 23ms ok', Look.done),
      ('SPAN  engine  sync 23ms error', Look.failed),
    ]) {
      final line = '11:12:13 [phone/abc123] $body';
      final formatted = Look.logLine(line);
      expect(formatted.device, 'phone/abc123');
      expect(formatted.text.toPlainText(), line);
      expect(formatted.text.children![1].style!.color, color);
    }
  });
  test('history labels stay bounded without expanding nested payloads', () {
    final large = 'x' * (1 << 20);
    expect(previewOf(large).length, lessThan(100));
    expect(previewOf([large]), '[1 item]');
    expect(previewOf({'field': large}), '{1 field}');
  });

  test('mixed recording exposes gaps, searchable state history and causal navigation', () {
    final v = Viewer()
      ..load([(name: 'diagnostics.jsonl', text: diagnosticLines())]);
    addTearDown(v.dispose);
    expect(v.issueCount, 1);
    expect(v.omittedValues, isTrue);
    expect(v.all, hasLength(2), reason: 'catalog noise is hidden by default');
    expect(
      Viewer.hasProblems(v.all.first),
      isTrue,
      reason: 'the recorded late reply proves a caller timeout',
    );
    v.query = 'house.state';
    expect(
      v.conversations,
      hasLength(3),
      reason: 'both writes and catalog event match',
    );
    v.query = '';
    v.select(v.all.first);
    expect(v.tree.single.decisions.single.event, 'access.allowed');
    v.choose(v.tree.single.children.single);
    expect(v.stateHistory.map((w) => w.id), ['first-write', 'second-write']);
    v.chooseMessage(v.stateHistory.last);
    expect(v.node!.id, 'second-write');
    expect(v.selected!.id, 'second-write');
    v.load([(name: 'replacement.jsonl', text: diagnosticLines())]);
    expect(v.node, isNull);
    expect(v.issueCount, 1);
  });

  testWidgets(
    'diagnostic details distinguish omitted values, unresolved causes and late replies',
    (tester) async {
      final v = Viewer()
        ..load([(name: 'diagnostics.jsonl', text: diagnosticLines())]);
      addTearDown(v.dispose);
      v.select(v.all.first);
      v.choose(v.tree.single);
      await tester.binding.setSurfaceSize(const Size(1500, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final boundary = GlobalKey();
      final fontPath = Platform.environment['PARLANCE_VIEWER_FONT'];
      if (fontPath != null) {
        await tester.runAsync(() async {
          final bytes = await File(fontPath).readAsBytes();
          for (final family in ['Roboto', 'monospace']) {
            await (FontLoader(
              family,
            )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
          }
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        });
      }
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: ParlanceConsoleApp(viewer: v),
        ),
      );
      await tester.pump();
      expect(find.textContaining('values omitted'), findsOneWidget);
      expect(find.text('not recorded'), findsOneWidget);
      expect(find.text('unavailable-parent'), findsOneWidget);
      expect(find.text('caller received'), findsOneWidget);
      expect(find.text('Admission and retries'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final path = Platform.environment['PARLANCE_VIEWER_SCREENSHOT'];
      if (path != null) {
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await render.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(path).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    },
  );

  testWidgets('open a journal: its conversations, one as a tree, a message '
      'in it', (tester) async {
    final text = await tester.runAsync(journalLines);
    final v = Viewer()..load([(name: 'journal-2026-10-28.jsonl', text: text!)]);
    await tester.binding.setSurfaceSize(const Size(1500, 900));
    await tester.pumpWidget(ParlanceConsoleApp(viewer: v));

    expect(find.text('studio/chat.say'), findsNWidgets(2));
    expect(find.textContaining('2 conversations'), findsOneWidget);

    await tester.tap(find.text('studio/chat.say').first);
    await tester.pump();
    expect(find.text('studio/chat.line'), findsOneWidget);
    expect(find.text('studio/clip.save'), findsOneWidget);
    expect(find.text('studio/clip.cover'), findsOneWidget);
    expect(find.text('studio/clip.last'), findsOneWidget);

    await tester.tap(find.text('studio/clip.cover'));
    await tester.pump();
    expect(find.text('refused'), findsOneWidget);
    expect(find.text('How it came about'), findsOneWidget);

    await tester.tap(find.byType(FilterChip));
    await tester.pump();
    expect(find.text('2 of 2'), findsOneWidget, reason: 'both had a refusal');
    await tester.binding.setSurfaceSize(null);
  });

  test('playback shows only what had happened by then, and jumps a quiet '
      'stretch', () async {
    final text = await journalLines();
    final v = Viewer()..load([(name: 'j.jsonl', text: text)]);
    final talks = v.all;
    expect(talks, hasLength(2));
    v.seek(talks.first.started);
    expect(v.conversations.map((c) => c.id), ['viewer/twitch.7#irc:1']);
    v.select(talks.first);
    expect(v.tree.single.children, isEmpty, reason: 'only the call so far');
    v.seek(v.last!);
    expect(v.conversations, hasLength(2));
    expect(v.tree.single.children.single.children, hasLength(2));

    v.seek(v.first!);
    v.play();
    v.speed = 1;
    v.advance(const Duration(milliseconds: 1));
    expect(v.playing, isTrue);
    v.advance(const Duration(hours: 1));
    expect(v.playing, isFalse, reason: 'it came to the end');
    expect(v.playhead, v.last);
    v.stop();
    expect(v.playhead, isNull);
  });

  test('a line that is no entry is skipped; files go in the order of '
      'their days', () async {
    final text = await journalLines();
    final lines = const LineSplitter().convert(text);
    final v = Viewer()
      ..load([
        (name: 'journal-2026-10-29.jsonl', text: lines.skip(3).join('\n')),
        (
          name: 'journal-2026-10-28.jsonl',
          text: '${lines.take(3).join('\n')}\n{"cut',
        ),
      ]);
    expect(v.files, ['journal-2026-10-28.jsonl', 'journal-2026-10-29.jsonl']);
    expect(v.entries, hasLength(lines.length));
  });
}
