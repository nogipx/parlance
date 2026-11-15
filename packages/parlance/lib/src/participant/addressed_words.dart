part of 'participant.dart';

final class _StateAt<T> implements IStateWord<T> {
  _StateAt(this.word, this.target);
  final IStateWord<T> word;
  final Principal Function() target;
  @override
  late final String name = WordAddress(target().whole, word.name).toString();
  @override
  Shape<T> get shape => word.shape;
  @override
  String? get key => word.key;
}

final class _CommandAt<P, R> implements ICommandWord<P, R> {
  _CommandAt(this.word, this.target);
  final ICommandWord<P, R> word;
  final Principal Function() target;
  @override
  late final String name = WordAddress(target().whole, word.name).toString();
  @override
  RecordShape<P> get params => word.params;
  @override
  Shape<R>? get returns => word.returns;
}

final class _QueryAt<P, R> implements IQueryWord<P, R> {
  _QueryAt(this.word, this.target);
  final IQueryWord<P, R> word;
  final Principal Function() target;
  @override
  late final String name = WordAddress(target().whole, word.name).toString();
  @override
  RecordShape<P> get params => word.params;
  @override
  Shape<R> get returns => word.returns;
}

final class _FactAt<T> implements IFactWord<T> {
  _FactAt(this.word, this.target);
  final IFactWord<T> word;
  final Principal Function() target;
  @override
  late final String name = WordAddress(target().whole, word.name).toString();
  @override
  Shape<T> get shape => word.shape;
}

final class _ServerStreamAt<P, T> implements IServerStreamWord<P, T> {
  _ServerStreamAt(this.word, this.target);
  final IServerStreamWord<P, T> word;
  final Principal Function() target;
  @override
  late final String name = WordAddress(target().whole, word.name).toString();
  @override
  RecordShape<P> get params => word.params;
  @override
  Shape<T> get shape => word.shape;
}

final class _ClientStreamAt<P, I, R> implements IClientStreamWord<P, I, R> {
  _ClientStreamAt(this.word, this.target);
  final IClientStreamWord<P, I, R> word;
  final Principal Function() target;
  @override
  late final String name = WordAddress(target().whole, word.name).toString();
  @override
  RecordShape<P> get params => word.params;
  @override
  Shape<I> get input => word.input;
  @override
  Shape<R> get returns => word.returns;
}

final class _BidiStreamAt<P, I, O> implements IBidiStreamWord<P, I, O> {
  _BidiStreamAt(this.word, this.target);
  final IBidiStreamWord<P, I, O> word;
  final Principal Function() target;
  @override
  late final String name = WordAddress(target().whole, word.name).toString();
  @override
  RecordShape<P> get params => word.params;
  @override
  Shape<I> get input => word.input;
  @override
  Shape<O> get shape => word.shape;
}

IWord _wordAt(IWord word, Principal Function() target) => switch (word) {
  IStateWord() => _StateAt(word, target),
  ICommandWord() => _CommandAt(word, target),
  IQueryWord() => _QueryAt(word, target),
  IFactWord() => _FactAt(word, target),
  IServerStreamWord() => _ServerStreamAt(word, target),
  IClientStreamWord() => _ClientStreamAt(word, target),
  IBidiStreamWord() => _BidiStreamAt(word, target),
  _ => throw ArgumentError('unknown word ${word.name}'),
};
