/// The registry over rpc_dart (SPEC §14): a session per remote participant,
/// a typed client and a mirror that resumes the feed after a lost
/// connection.
library;

export 'src/remote/contract.dart';
export 'src/remote/remote.dart';
export 'src/remote/typed.dart';
