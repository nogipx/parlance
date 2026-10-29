part of 'participant.dart';

/// A part of a remote participant (SPEC §22.3): the participant's own
/// machinery, each thing it asks told as the part's (`as`).
final class _Part implements IRawParticipant {
  _Part(this._root, this.who);
  final RemoteParticipant _root;

  @override
  final Principal who;

  @override
  Set<String> get vocabularies => _root.vocabularies;

  @override
  WordAccess get access => _root.access;

  @override
  Clock get clock => _root.clock;

  @override
  Object? read(String state, {String? key}) => _root.read(state, key: key);

  @override
  T? readAs<T>(String state, Shape<T> shape, {String? key}) =>
      _root.readAs(state, shape, key: key);

  @override
  Map<String?, Object?> readAll(String state) => _root.readAll(state);

  @override
  Future<Map<String?, Object?>> fetch(String state, {bool keep = true}) =>
      _root.fetch(state, keep: keep);

  @override
  Future<Map<String, Object?>> describe() => _root.describe();

  @override
  Future<Explanation> explain(String state, {String? key}) =>
      _root.explain(state, key: key);

  @override
  Stream<void> get catalogChanges => _root.catalogChanges;

  @override
  Stream<Object?> watch(String state, {String? key}) =>
      _root.watch(state, key: key);

  @override
  Stream<T?> watchAs<T>(String state, Shape<T> shape, {String? key}) =>
      _root.watchAs(state, shape, key: key);

  @override
  Stream<void> changes(Set<String> states) => _root.changes(states);

  @override
  Stream<FactMessage> facts(String fact) => _root.facts(fact);

  @override
  Stream<(T, FactMessage)> factsAs<T>(String fact, Shape<T> shape) =>
      _root.factsAs(fact, shape);

  @override
  Future<List<FactMessage>> recent(String fact, int count) =>
      _root.recent(fact, count);

  @override
  Future<CallResult<Object?>> call(
    String command,
    Map<String, Object?> params, {
    String? id,
    Cause? cause,
  }) => _root._call(command, params, id: id, cause: cause, as: who);

  @override
  Future<CallResult<Object?>> callAs(
    String command,
    Object? params,
    Shape<Object?> shape, {
    String? id,
    Cause? cause,
  }) => call(
    command,
    shape.toJson(params)! as Map<String, Object?>,
    id: id,
    cause: cause,
  );

  @override
  bool get synced => _root.synced;

  @override
  WordStatus status(String word) => _root.status(word);

  @override
  Stream<WordStatus> statusChanges(String word) => _root.statusChanges(word);

  @override
  Descriptor? descriptor(String word) => _root.descriptor(word);

  @override
  void builtAgainst(Iterable<IWord> words, {String? from}) {
    _root._builtAgainst(schemasOf(words), from, who);
    _root._watchBuilt(words, from);
  }

  @override
  IStateHandle defineState(StateDescriptor d, {Shape<Object?>? shape}) =>
      _root._defineState(d, who);

  @override
  IHandle defineCommand(
    CommandDescriptor d,
    CommandHandler handler, {
    Availability? available,
    Shape<Object?>? params,
    Shape<Object?>? returns,
  }) => _root._defineCommand(d, handler, available, who);

  @override
  IHandle defineQuery(
    QueryDescriptor d,
    CommandHandler handler, {
    Availability? available,
    Shape<Object?>? params,
    Shape<Object?>? returns,
  }) => _root._defineCommand(d, handler, available, who);

  @override
  IFactHandle defineFact(FactDescriptor d, {Shape<Object?>? shape}) =>
      _root._defineFact(d, who);

  @override
  IHandle addGuard(String id, GuardCheck check) =>
      _root._addGuard(id, check, who);

  @override
  IHandle registerKind(EntityKind kind) => _root._registerKind(kind, who);

  @override
  void entitiesChanged(String kind) => _root.entitiesChanged(kind);

  @override
  void availabilityChanged(String command) =>
      _root.availabilityChanged(command);

  @override
  void availabilityMayHaveChanged() => _root._checkAvailability();

  @override
  void batch(void Function() writes) => _root.batch(writes);

  @override
  Future<void> settle() => _root.settle();

  late final OwnerGroup _group = OwnerGroup(this);

  @override
  Future<void> attach(Map<String, IOwner> owners) {
    _group.attach(owners);
    return _root.flush();
  }

  @override
  void sync() => _group.sync();

  @override
  IRawParticipant child(String name) => _root._partOf(who.child(name));

  @override
  void dispose() {
    _group.dispose();
    _root._withdraw(who);
  }
}
