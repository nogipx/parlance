part of 'registry.dart';

/// The declaration stays with its handles; the host's policy is stored separately.
extension on Registry {
  Descriptor? _declared(String word) {
    final n = canonical(word);
    return _states[n]?.descriptor ??
        _commands[n]?.descriptor ??
        _facts[n]?.descriptor ??
        _streams[n]?.descriptor;
  }

  bool _invoked(Descriptor d) =>
      d is CallableDescriptor || (d is DataStreamDescriptor && d.input != null);

  Callers? _policy(Descriptor d) {
    final override = _wordAccess[d.name];
    if (_invoked(d)) {
      return override?.callers ??
          switch (d) {
            CallableDescriptor() => d.callers,
            DataStreamDescriptor() => d.readers,
            _ => null,
          };
    }
    return override?.readers ??
        switch (d) {
          StateDescriptor() => d.readers,
          FactDescriptor() => d.readers,
          DataStreamDescriptor() => d.readers,
          _ => null,
        };
  }

  Access _accessFor(String word, Principal by) {
    final d = _declared(word);
    return d == null ? Access.allow : _policy(d)?.accessOf(by) ?? Access.allow;
  }

  D _effective<D extends Descriptor>(D d) {
    if (!_wordAccess.containsKey(d.name)) return d;
    final field = d is CallableDescriptor ? 'callers' : 'readers';
    final json = {...d.toJson()};
    final policy = _policy(d);
    if (policy == null) {
      json.remove(field);
    } else {
      json[field] = policy.toJson();
    }
    return Descriptor.fromJson(json) as D;
  }

  D? _effectiveOrNull<D extends Descriptor>(D? d) =>
      d == null ? null : _effective(d);

  void _checkAccess(Descriptor d) {
    final access = _wordAccess[d.name];
    if (access == null) return;
    if ((_invoked(d) ? access.readers : access.callers) != null) {
      throw ArgumentError('wrong access field for ${d.name}');
    }
  }

  void _setAccess(WordAddress address, WordAccess? access) {
    refuseInQuery('change access to $address');
    if (_disposing) throw StateError('the host ended');
    final word = canonical(address.toString());
    Callers? copy(Callers? p) {
      if (p == null) return null;
      p.check();
      return Callers(Map.unmodifiable(p.rules));
    }

    final next = access == null
        ? null
        : WordAccess(
            readers: copy(access.readers),
            callers: copy(access.callers),
          );
    final before = _wordAccess[word];
    if (next == null || (next.readers == null && next.callers == null)) {
      _wordAccess.remove(word);
    } else {
      _wordAccess[word] = next;
    }
    try {
      if (_declared(word) case final d?) _checkAccess(d);
    } on Object {
      if (before == null) {
        _wordAccess.remove(word);
      } else {
        _wordAccess[word] = before;
      }
      rethrow;
    }
    Map<String, Object?> json(WordAccess? a) => {
      'readers': a?.readers?.toJson(),
      'callers': a?.callers?.toJson(),
    };
    if (jsonEquals(json(before), json(_wordAccess[word]))) return;
    _accessRevisions[word] = accessRevision(word) + 1;
    // Revocation closes streams synchronously before any more values are admitted.
    for (final observation in _activeStreams.values.toList()) {
      if (canonical(observation.word) == word &&
          _accessFor(word, observation.cause.by) == Access.deny) {
        _streamLeases[observation.id]?.end(
          StreamFailure(
            StreamFailureCode.notPermitted,
            '${observation.cause.by} may not use $word',
          ),
        );
      }
    }
    _accessChanges.add(word);
    _announce(AccessChanged(word));
  }

  Map<String, Object?> _accessEvidence(String word, Principal by) {
    final d = _declared(word);
    final policy = d == null ? null : _policy(d);
    String? selector;
    for (Principal? p = by; p != null; p = p.parent) {
      if (policy?.rules.containsKey(p.selector) ?? false) {
        selector = p.selector;
        break;
      }
    }
    selector ??= policy?.rules.containsKey('*') == true ? '*' : null;
    return {
      'revision': accessRevision(word),
      'access': _accessFor(word, by).name,
      'selector': selector,
      'source': _wordAccess.containsKey(canonical(word))
          ? 'host'
          : 'declaration',
    };
  }

  void _warnAccess(
    String word,
    Principal by,
    AccessOperation operation, {
    String? id,
    Cause? cause,
  }) {
    if (operation == AccessOperation.read && isSubscriptionRead) return;
    if (_accessFor(word, by) != Access.warn) return;
    _notice(
      word,
      'access.warn',
      cause: cause ?? Cause(by),
      data: {
        'operation': operation.name,
        'call': id,
        ..._accessEvidence(word, by),
      },
    );
    final warning = AccessWarning(
      word: word,
      by: by,
      operation: operation,
      at: clock.now(),
      id: id,
      cause: cause,
    );
    if (!_accessWarnings.isClosed) _accessWarnings.add(warning);
    if (_accessLog.isEnabled(RpcLogLevel.warning)) {
      _accessLog.warning('unexpected access', data: warning.toJson());
    } else if (!_traced) {
      assert(() {
        developer.log(
          'unexpected access: ${warning.toJson()}',
          name: 'parlance.access',
          level: 900,
        );
        return true;
      }());
    }
  }
}
