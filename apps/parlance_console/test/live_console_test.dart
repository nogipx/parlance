import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:parlance_console/main.dart';
import 'package:parlance_console/src/console/client.dart';
import 'package:parlance_console/src/viewer.dart';

void main() {
  testWidgets('live logs, pause and read-only host inspection', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 750));
    final input = StreamController<String>();
    final output = StringBuffer();
    final client = ConsoleClient(input.stream, output);
    final viewer = Viewer();
    var message = 'first edit';
    var sharingJournal = false;
    var wifi = false;
    const phoneLine = '10:00:00 [phone] INFO sync  connected';
    const desktopLine = '10:00:00 [desktop] INFO sync  connected';

    Color rowColor(String text) => tester
        .widgetList<ColoredBox>(
          find.ancestor(of: find.text(text), matching: find.byType(ColoredBox)),
        )
        .firstWhere((box) => box.child is Row)
        .color;

    Future<void> respond() async {
      for (var round = 0; round < 8; round++) {
        await tester.pump();
        final lines = output.toString().trim();
        output.clear();
        if (lines.isEmpty) continue;
        for (final line in lines.split('\n')) {
          final request = jsonDecode(line) as Map<String, dynamic>;
          if (request['id'] == null) continue;
          Object? result;
          switch (request['method']) {
            case 'console/wifi':
              wifi = request['params']['enabled'] as bool? ?? wifi;
              result = {
                'enabled': wifi,
                if (wifi) 'android': 'ws://192.0.2.1:9444',
                if (wifi) 'ios': 'wss://192.0.2.1:9443',
              };
            case 'initialize':
              result = {'protocolVersion': '2025-06-18'};
            case 'tools/list':
              result = {
                'tools': [
                  {'name': 'h1_read'},
                  {'name': 'h1_targets'},
                  {'name': 'h1_call'},
                ],
              };
            case 'tools/call':
              final params = request['params'] as Map<String, dynamic>;
              final content = switch (params['name']) {
                'hosts' =>
                  sharingJournal
                      ? '[{"prefix":"h2","app":"notes","device":"phone","journal":true}]'
                      : '[{"prefix":"h1","app":"notes","device":"phone"}]',
                'h2_journal' => jsonEncode({
                  'lines': [
                    if ((params['arguments'] as Map)['after'] == 0)
                      jsonEncode({
                        'kind': 'diagnostic',
                        'epoch': 'phone',
                        'n': 1,
                        'id': 'observed',
                        'word': 'notes/run',
                        'event': 'word.defined',
                        'cause': {
                          'by': {'kind': 'notes'},
                        },
                        'at': '2026-11-26T12:00:00Z',
                      }),
                  ],
                  'cursor': 1,
                  'more': false,
                  'ended': false,
                  'dropped': 0,
                }),
                'rpc_log_sources' =>
                  'Devices (1):\n  phone [notes] since 00:00:00',
                'rpc_log_get_logs' =>
                  'Found 3 records:\n$message\n$phoneLine\n$desktopLine',
                'h1_describe' => '{"states":[{"name":"notes/notes.phase"}],"facts":[{"name":"notes/notes.edited"}],"commands":[]}',
                'h1_targets' => jsonEncode([
                  {
                    'vocabularies': [
                      {
                        'words': [
                          {
                            'address': 'notes/notes.phase',
                            'is': 'state',
                            'status': 'ready',
                          },
                          {
                            'address': 'notes/notes.edited',
                            'is': 'fact',
                            'status': 'ready',
                          },
                          {
                            'address': 'notes/notes.reset',
                            'is': 'command',
                            'status': 'notPermitted',
                            'why': 'Only the owner can reset',
                          },
                          {
                            'address': 'notes/notes.preview',
                            'is': 'query',
                            'status': 'notPermitted',
                          },
                          {
                            'address': 'notes/notes.updates',
                            'is': 'serverStream',
                            'status': 'ready',
                          },
                        ],
                      },
                    ],
                  },
                ]),
                'h1_recent_facts' => '[{"at":"2026-11-26T12:00:00Z","by":"notes","payload":"saved"}]',
                'h1_read' => '"ready"',
                _ => throw StateError('unexpected tool: ${params['name']}'),
              };
              result = {
                'content': [
                  {'text': content},
                ],
              };
            default:
              fail('unexpected request');
          }
          input.add(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': request['id'],
              'result': result,
            }),
          );
        }
      }
    }

    await tester.pumpWidget(ParlanceConsoleApp(viewer: viewer, client: client));
    await respond();
    expect(find.text('first edit'), findsOneWidget);
    final phoneColor = tester.widget<Icon>(find.byIcon(Icons.circle)).color!;
    expect(rowColor(phoneLine), phoneColor.withValues(alpha: 0.14));
    expect(rowColor(desktopLine), isNot(rowColor(phoneLine)));
    expect(rowColor('first edit'), Colors.transparent);
    await tester.tap(find.text('Wi-Fi'));
    await respond();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accept devices over Wi-Fi'));
    await respond();
    expect(find.text('ws://192.0.2.1:9444'), findsOneWidget);
    expect(find.byTooltip('Copy iPhone address'), findsOneWidget);
    await tester.tap(find.text('Accept devices over Wi-Fi'));
    await respond();
    expect(find.byTooltip('Copy Android address'), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Pause'));
    message = 'later edit';
    await tester.pump(const Duration(seconds: 1));
    await respond();
    expect(find.text('first edit'), findsOneWidget);
    await tester.tap(find.byTooltip('Resume'));
    await tester.pump(const Duration(seconds: 1));
    await respond();
    expect(find.text('later edit'), findsOneWidget);
    expect(rowColor(phoneLine), phoneColor.withValues(alpha: 0.14));
    await tester.tap(find.text('phone'));
    await respond();
    await tester.tap(find.text('Inspector'));
    await respond();
    expect(find.text('5 words'), findsOneWidget);
    expect(find.text('notes/notes.preview'), findsOneWidget);
    expect(find.text('notes/notes.updates'), findsOneWidget);
    await tester.tap(find.text('notes/notes.reset'));
    await tester.pump();
    expect(find.text('Only the owner can reset'), findsOneWidget);
    expect(find.text('call'), findsNothing);
    await tester.tap(find.text('notes/notes.phase'));
    await tester.pump();
    await tester.tap(find.text('read'));
    await respond();
    expect(find.text('"ready"'), findsOneWidget);
    expect(find.text('call'), findsNothing);
    await tester.tap(find.text('Journal'));
    await respond();
    expect(find.text('Live facts'), findsOneWidget);
    expect(find.text('"saved"'), findsOneWidget);
    sharingJournal = true;
    await tester.pump(const Duration(seconds: 1));
    await respond();
    expect(find.text('notes/run'), findsOneWidget);
    expect(find.byTooltip('Pause journal'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
    addTearDown(input.close);
    addTearDown(viewer.dispose);
  });
}
