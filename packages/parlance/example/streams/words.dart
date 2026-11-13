import 'package:parlance/schema.dart';

part 'words.g.dart';

/// Three distinct interactions with a document owner.
@Vocabulary('documents')
abstract class Documents {
  @ServerStreamWord('read')
  Stream<String> read({required String name});

  @ClientStreamWord('save', callers: Callers.anyone)
  Future<int> save(Stream<String> lines, {required String name});

  @BidiStreamWord('preview', callers: Callers.anyone)
  Stream<String> preview(Stream<String> lines, {String prefix = ''});
}

class DocumentStore extends DocumentsOwnerBase {
  final _documents = <String, List<String>>{};

  @override
  Stream<String> read({required String name}) =>
      Stream.fromIterable(List.of(_documents[name] ?? const []));

  @override
  Future<int> save(Stream<String> lines, {required String name}) async {
    final contents = await lines.toList();
    if (expired?.isCancelled ?? false) {
      throw const StreamFailure(
        StreamFailureCode.cancelled,
        'the upload was cancelled',
      );
    }
    _documents[name] = contents;
    return contents.length;
  }

  @override
  Stream<String> preview(Stream<String> lines, {String prefix = ''}) async* {
    await for (final line in lines) {
      yield '$prefix${line.trim()}';
    }
    // The sender has finished; the owner can still emit its final output.
    yield '${prefix}done';
  }
}
