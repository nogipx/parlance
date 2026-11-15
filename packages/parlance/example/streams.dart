import 'package:parlance/app.dart';
import 'package:rpc_dart/rpc_dart.dart';

import 'streams/words.dart';

Future<void> main() async {
  final host = Host();
  host.participant(const Principal('store'), owners: [DocumentStore()]);
  final (a, b) = RpcChannelTransport.pair();
  final server = RpcPeerEndpoint(transport: a);
  host.serve(const Principal('editor'), server);
  server.start();
  final endpoint = RpcPeerEndpoint(transport: b)..start();
  final participant = await Host.joinEndpoint(endpoint);
  final documents = IDocumentsClient(
    participant: participant,
    target: const Principal('store'),
  );
  try {
    final saved = await documents.save(
      Stream.fromIterable(['first line', 'second line']),
      name: 'notes',
    );
    print('Saved $saved lines');
    print('Read: ${await documents.read(name: 'notes').toList()}');
    print(
      'Preview: ${await documents.preview(Stream.fromIterable(['  first  ', '  second  ']), prefix: '> ').toList()}',
    );
  } finally {
    await participant.dispose();
    await endpoint.close();
    await server.close();
    await host.dispose();
  }
}
