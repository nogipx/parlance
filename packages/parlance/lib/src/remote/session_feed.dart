part of 'session.dart';

/// One feed of a session ([RemoteSession.onFeed]): the registry's feed as
/// the session follows it, handed to the connection as fast as it takes it.
/// It applies backpressure, so a slow client pauses it: what waits is held,
/// and ticks held past the session's `feedBacklog` are dropped.
final class _Feed {
  _Feed(this._s, WireFeedRequest request)
    : _last = request.since,
      _sent = request.since,
      _sentEpoch = request.epoch {
    out = StreamController<WireFeedItem>(
      onListen: _listen,
      onResume: _drain,
      onCancel: _stop,
    );
  }

  final RemoteSession _s;
  late final StreamController<WireFeedItem> out;
  StreamSubscription<FeedItem>? _items;
  StreamSubscription<CatalogChange>? _catalog;

  /// Whether the connection listens: until then it gets no items nor
  /// catch-ups from the session.
  bool listened = false;

  /// The last seq the feed took: a tick it takes starts after it, so a
  /// tick left out (nothing in it the session follows) leaves no gap.
  int? _last;

  /// The last seq it handed to the connection, and of which epoch: the
  /// client's until the feed hands it one of this registry's.
  int? _sent;
  String? _sentEpoch;

  /// The last seq of a tick it saw, sent or left out.
  int? _seen;

  /// The commands that could not run when the feed last told, and why.
  Map<String, String> _unavailable = const {};

  /// What waits while the connection is not taking more; ticks carry
  /// their seq.
  final List<(WireFeedItem, int?)> _held = [];
  bool _behind = false;
  bool _factsDropped = false;

  Registry get _registry => _s.registry;

  void _listen() {
    listened = true;
    _describe();
    _catalog = _registry.catalogChanges.listen((_) => _describe());
    _follow();
  }

  void _hand((WireFeedItem, int?) i) {
    out.add(i.$1);
    if (i.$2 case final seq?) {
      _sent = seq;
      _sentEpoch = _registry.epoch;
    }
  }

  /// Too far behind: what it holds of ticks goes, the rest stays (the
  /// catalog last told, a subscription's values), and the feed follows
  /// again from the last seq sent once the client takes more.
  void _drop() {
    _factsDropped |= _held.any(
      (i) =>
          i.$1.kind == 'tick' &&
          (i.$1.json['facts'] as List? ?? const []).isNotEmpty,
    );
    // Of the catalog and of what cannot run, only the last told counts.
    final lastOf = {
      for (final i in _held)
        if (i.$1.kind == 'catalog' || i.$1.kind == 'unavailable') i.$1.kind: i,
    };
    _held.retainWhere((i) => i.$1.kind == 'values' || lastOf[i.$1.kind] == i);
    if (!_behind) {
      _behind = true;
      unawaited(_items?.cancel());
      _items = null;
    }
  }

  void send(WireFeedItem item, [int? seq]) {
    if (!out.isPaused && _held.isEmpty) return _hand((item, seq));
    _held.add((item, seq));
    if (_held.length > _s.feedBacklog) _drop();
  }

  /// Tells the client, by an empty tick, that the ticks it was not sent
  /// went by up to [seq]: a call answered there returns at once rather
  /// than wait for a tick that never comes.
  void catchUp(int seq) {
    final through = _seen;
    final from = _last;
    if (through == null || from == null || from >= seq) return;
    final to = through < seq ? through : seq;
    if (to <= from) return;
    _last = to;
    send(
      WireFeedItem(
        'tick',
        Tick(
          epoch: _registry.epoch,
          from: from + 1,
          to: to,
          changes: const [],
          facts: const [],
        ).toJson(),
      ),
      to,
    );
  }

  void _drain() {
    while (_held.isNotEmpty && !out.isPaused) {
      _hand(_held.removeAt(0));
    }
    if (_held.isEmpty && _behind && !out.isPaused) {
      _behind = false;
      _last = _sent;
      _follow();
    }
  }

  void _describe() {
    final d = _registry.describeFor(_s.principal);
    _unavailable = d['unavailable']! as Map<String, String>;
    send(WireFeedItem('catalog', d));
  }

  /// After a tick: whether a command came to run or stopped, told as the
  /// whole set when it moved.
  void _availability() {
    final now = _registry.unavailable;
    if (_sameMap(now, _unavailable)) return;
    _unavailable = now;
    send(WireFeedItem('unavailable', {'unavailable': now}));
  }

  void _follow() {
    _items = _registry.feed(epoch: _sentEpoch, since: _sent).listen((i) {
      switch (i) {
        case Snapshot():
          _last = i.seq;
          send(
            WireFeedItem('snapshot', {
              ...Snapshot(
                epoch: i.epoch,
                seq: i.seq,
                states: {
                  for (final e in i.states.entries)
                    if (_s._carries(e.key)) e.key: e.value,
                },
                factsLost: i.factsLost || _factsDropped,
              ).toJson(),
              'subscription': _s._subscription,
            }),
            i.seq,
          );
          _factsDropped = false;
        case Tick():
          _seen = i.to;
          final t = _s._tickOf(i, _last == null ? i.from : _last! + 1);
          if (t != null) {
            _last = i.to;
            send(WireFeedItem('tick', t.toJson()), i.to);
          } else if (i.to <= _s._owed) {
            // Nothing in it the session follows, but a call of its
            // waits for this seq: told it went by, empty.
            catchUp(i.to);
          }
          _availability();
      }
    });
  }

  /// The connection stopped listening.
  Future<void> _stop() async {
    _s._feeds.remove(this);
    _held.clear();
    await _items?.cancel();
    await _catalog?.cancel();
  }

  /// The session ended: nothing more goes to it.
  Future<void> end() async {
    await _stop();
    await out.close();
  }
}

bool _sameMap(Map<String, String> a, Map<String, String> b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);
