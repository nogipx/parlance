/// The host of widlet guests: one registry, the app's own words, and a
/// session for each guest it loads, its words in its own vocabulary.
library;

import 'package:host_words/host_words.dart';
import 'package:parlance/participant.dart';
import 'package:parlance/registry.dart';
import 'package:parlance/remote.dart';
import 'package:rpc_dart/rpc_dart.dart';

/// Who acts in the app.
abstract final class Who {
  static const app = Principal('app');
  static const user = Principal('user');
  static Principal widlet(String id) =>
      Principal('widlet', Principal.levelOf(id));

  /// Who may call a guest's commands, and the app's: the guests and the
  /// user. The host says it, never a guest of itself.
  static const callers = Callers({
    'widlet': Access.allow,
    'user': Access.allow,
  });
}

/// The owner of the app's words.
final class AppHost extends AppOwner {
  AppHost() {
    dark = false;
  }

  final List<String> toasts = [];

  @override
  void toast({required String text}) => toasts.add(text);
}

/// The app's registry and its words.
final class Host {
  Host() {
    registry
        .participant(
          Who.app,
          vocabularies: [appWords],
          access: const WordAccess(call: Who.callers),
        )
        .attach({'shell': app});
  }

  final Registry registry = Registry();
  final AppHost app = AppHost();
  final Map<String, RemoteSession> _guests = {};

  /// Serves the guest [id] over [endpoint]: a participant of its own, its
  /// words named in the vocabulary of its id (a guest's words come at run
  /// time), its commands called by the guests and the user.
  RemoteSession load(String id, RpcPeerEndpoint endpoint) {
    final session = registry
        .participant(
          Who.widlet(id),
          vocabularies: [WordSet.open(id)],
          access: const WordAccess(call: Who.callers),
        )
        .serve(endpoint);
    _guests[id] = session;
    return session;
  }

  /// Unloads the guest [id]: its session ends, and its words go with it.
  void unload(String id) => _guests.remove(id)?.close();

  /// Ends it all: the registry takes its participants and the guests'
  /// sessions with it.
  Future<void> dispose() => registry.dispose();
}
