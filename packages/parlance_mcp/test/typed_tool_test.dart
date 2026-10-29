import 'package:parlance_mcp/parlance_mcp.dart';
import 'package:parlance/tools.dart';
import 'package:test/test.dart';

sealed class Op {
  const Op();
}

final class Add extends Op {
  const Add(this.name, {this.ref});
  final String name;
  final String? ref;
}

final class Remove extends Op {
  const Remove(this.id);
  final String id;
}

final _ops = UnionShape<Op>(
  'op',
  {
    'add': RecordShape<Add>(
      {
        'name': Part(Plain(TextType()), description: 'what it is called'),
        'ref': Part(Plain(TextType()), optional: true),
      },
      to: (a) => {'name': a.name, 'ref': a.ref},
      from: (m) => Add(m['name']! as String, ref: m['ref'] as String?),
    ),
    'remove': RecordShape<Remove>(
      {'id': Part(Plain(TextType()))},
      to: (r) => {'id': r.id},
      from: (m) => Remove(m['id']! as String),
    ),
  },
  tagOf: (o) => switch (o) {
    Add() => 'add',
    Remove() => 'remove',
  },
);

typedef Edit = ({String label, List<Op> ops});

final _edit = RecordShape<Edit>(
  {
    'label': Part(Plain(TextType()), description: 'for the undo menu'),
    'ops': Part(ListShape(_ops)),
  },
  to: (e) => {'label': e.label, 'ops': e.ops},
  from: (m) => (label: m['label']! as String, ops: m['ops']! as List<Op>),
);

void main() {
  final seen = <Edit>[];
  final tool = McpTool.typed(
    name: 'edit',
    description: 'Changes things, as one step.',
    params: _edit,
    run: (e) async {
      seen.add(e);
      return McpResult('${e.ops.length}');
    },
  );

  test('the schema is the shape\'s: fields, descriptions, variants', () {
    final s = tool.toMcp()['inputSchema']! as Map;
    expect(s['required'], ['label', 'ops']);
    final props = s['properties']! as Map;
    expect((props['label'] as Map)['description'], 'for the undo menu');
    final variants = ((props['ops'] as Map)['items'] as Map)['oneOf'] as List;
    final add = variants.first as Map;
    expect((add['properties'] as Map)['op'], {'const': 'add'});
    expect(add['required'], ['op', 'name']);
    expect(add['additionalProperties'], isFalse);
    expect(
      ((add['properties'] as Map)['name'] as Map)['description'],
      'what it is called',
    );
  });

  test('arguments come typed; what does not pass says where', () async {
    final ok = await tool.run({
      'label': 'Tidy',
      'ops': [
        {'op': 'add', 'name': 'Cam', 'ref': 'c'},
        {'op': 'remove', 'id': 'x'},
      ],
    });
    expect(ok.error, isFalse);
    expect(seen.single.ops.first, isA<Add>().having((a) => a.ref, 'ref', 'c'));
    expect(seen.single.ops.last, isA<Remove>());
    final missing = await tool.run({
      'label': 'Tidy',
      'ops': [
        {'op': 'add'},
      ],
    });
    expect(missing.error, isTrue);
    expect(missing.text, 'ops.0.name: missing');
    final unknown = await tool.run({
      'label': 'Tidy',
      'ops': [
        {'op': 'paint'},
      ],
    });
    expect(unknown.text, 'ops.0.op: one of add, remove');
    final extra = await tool.run({
      'label': 'Tidy',
      'ops': [
        {'op': 'remove', 'id': 'x', 'force': true},
      ],
    });
    expect(extra.text, 'ops.0.force: unknown field');
  });

  test('a union goes to JSON and back', () {
    final json = _ops.toJson(const Add('Cam'));
    expect(json, {'op': 'add', 'name': 'Cam'});
    expect(_ops.fromJson(json), isA<Add>());
    expect(ValueType.fromJson(_ops.type.toJson()), isA<OneOfType>());
  });

  test('a map takes any keys, its values typed', () async {
    final files = <Map<String, String>>[];
    final t = McpTool.typed(
      name: 'write',
      description: 'Writes files.',
      params: RecordShape<({Map<String, String> files})>(
        {'files': Part(MapShape(Plain(TextType())))},
        to: (a) => {'files': a.files},
        from: (m) => (files: m['files']! as Map<String, String>),
      ),
      run: (a) async {
        files.add(a.files);
        return const McpResult('ok');
      },
    );
    expect(((t.toMcp()['inputSchema']! as Map)['properties'] as Map)['files'], {
      'type': 'object',
      'additionalProperties': {'type': 'string'},
    });
    await t.run({
      'files': {'main.js': 'x'},
    });
    expect(files.single, {'main.js': 'x'});
    final bad = await t.run({
      'files': {'main.js': 3},
    });
    expect(bad.text, 'files.main.js: expected text');
  });
}
