import 'package:http/http.dart' as http;

import 'viewer.dart';

/// Loads into [viewer] the journal at [url] (a file served beside the
/// viewer, or anywhere that lets it be read): what `?journal=` names.
Future<void> loadFrom(Viewer viewer, Uri url) async {
  try {
    final r = await http.get(url);
    if (r.statusCode != 200) {
      viewer.fail('$url: ${r.statusCode} ${r.reasonPhrase ?? ''}'.trim());
      return;
    }
    final name = url.pathSegments.isEmpty ? '$url' : url.pathSegments.last;
    viewer.load([(name: name, text: r.body)]);
  } on Object catch (e) {
    viewer.fail('$url: $e');
  }
}
