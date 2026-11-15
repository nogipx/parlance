import 'dart:async';
import 'cause.dart';
import 'descriptors.dart';

/// Default or host-overridden access to published words.
/// Null fields inherit the word's declared policy. Each non-null selector map
/// replaces the corresponding policy as a whole.
final class WordAccess {
  /// Access defaults, or the fields to override for an exact word address.
  const WordAccess({this.readers, this.callers});

  /// Readers of states, facts and server streams; null inherits the declaration.
  final Callers? readers;

  /// Callers of commands, queries and input streams; null inherits.
  final Callers? callers;

  /// No overrides or participant defaults.
  static const none = WordAccess();
}

/// A real interaction that may reveal an unexpected module dependency.
enum AccessOperation {
  /// A value, recent facts or an explanation was requested.
  read,

  /// A state or fact listener was installed.
  subscribe,

  /// A command was invoked.
  call,

  /// A read-only query was invoked.
  query,

  /// A data stream was opened.
  openStream,
}

/// An allowed interaction whose effective rule is Access.warn.
/// Contains routing and causal context, never arguments or element payloads.
final class AccessWarning {
  /// The library records a warning when an interaction reaches its access check.
  const AccessWarning({
    required this.word,
    required this.by,
    required this.operation,
    required this.at,
    this.id,
    this.cause,
  });

  /// The full target/word address used by the caller.
  final String word;

  /// The exact caller, including its owner when applicable.
  final Principal by;

  /// The operation, independently of the word's data types.
  final AccessOperation operation;

  /// Time on the host's clock.
  final DateTime at;

  /// A call or streaming-operation ID, when present.
  final String? id;

  /// Verified attribution and causal context, when available.
  final Cause? cause;

  /// Structured diagnostics for logs and inspectors.
  Map<String, Object> toJson() => {
    'word': word,
    'by': by.toJson(),
    'operation': operation.name,
    'at': at.toUtc().toIso8601String(),
    'id': ?id,
    if (cause != null) 'cause': cause!.toJson(),
  };
}

const _subscriptionRead = #parlance.subscriptionRead;

/// Internal snapshots of an existing subscription do not create read warnings.
R readingSubscription<R>(R Function() read) =>
    runZoned(read, zoneValues: {_subscriptionRead: true});

/// Whether the current read only samples an already admitted subscription.
bool get isSubscriptionRead => Zone.current[_subscriptionRead] == true;
