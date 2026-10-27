// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'contract.dart';

// **************************************************************************
// RpcDartGenerator
// **************************************************************************

// ignore_for_file: type=lint, unused_element

class ParlanceContractNames {
  const ParlanceContractNames._();
  static const service = 'Parlance';
  static String instance(String suffix) => '$service\_$suffix';
  static const describe = 'describe';
  static const feed = 'feed';
  static const invoke = 'call';
  static const why = 'why';
  static const recent = 'recent';
  static const subscribe = 'subscribe';
  static const define = 'define';
  static const undefine = 'undefine';
  static const write = 'set';
  static const emit = 'emit';
  static const apply = 'apply';
}

class ParlanceContractCodecs {
  const ParlanceContractCodecs._();
  static const codecRpcNull = RpcCodec<RpcNull>(RpcNull.fromJson);
  static const codecWireCallReply = RpcCodec<WireCallReply>(
    WireCallReply.fromJson,
  );
  static const codecWireCallRequest = RpcCodec<WireCallRequest>(
    WireCallRequest.fromJson,
  );
  static const codecWireDefine = RpcCodec<WireDefine>(WireDefine.fromJson);
  static const codecWireDescription = RpcCodec<WireDescription>(
    WireDescription.fromJson,
  );
  static const codecWireEmit = RpcCodec<WireEmit>(WireEmit.fromJson);
  static const codecWireFeedItem = RpcCodec<WireFeedItem>(
    WireFeedItem.fromJson,
  );
  static const codecWireFeedRequest = RpcCodec<WireFeedRequest>(
    WireFeedRequest.fromJson,
  );
  static const codecWireJson = RpcCodec<WireJson>(WireJson.fromJson);
  static const codecWireName = RpcCodec<WireName>(WireName.fromJson);
  static const codecWireRecentRequest = RpcCodec<WireRecentRequest>(
    WireRecentRequest.fromJson,
  );
  static const codecWireSet = RpcCodec<WireSet>(WireSet.fromJson);
  static const codecWireSubscribe = RpcCodec<WireSubscribe>(
    WireSubscribe.fromJson,
  );
  static const codecWireTaken = RpcCodec<WireTaken>(WireTaken.fromJson);
  static const codecWireWhyRequest = RpcCodec<WireWhyRequest>(
    WireWhyRequest.fromJson,
  );
}

abstract class ParlanceContractPeer extends RpcPeerContract
    implements IParlanceContract {
  ParlanceContractPeer(
    RpcPeerEndpoint endpoint, {
    String? serviceNameOverride,
    RpcDataTransferMode dataTransferMode = RpcDataTransferMode.auto,
  }) : super(
         serviceNameOverride ?? ParlanceContractNames.service,
         endpoint,
         dataTransferMode: dataTransferMode,
         callerDataTransferMode: dataTransferMode,
       );

  @override
  void setup() {
    addUnaryMethod<RpcNull, WireDescription>(
      methodName: ParlanceContractNames.describe,
      handler: onDescribe,
      requestCodec: ParlanceContractCodecs.codecRpcNull,
      responseCodec: ParlanceContractCodecs.codecWireDescription,
    );
    addServerStreamMethod<WireFeedRequest, WireFeedItem>(
      methodName: ParlanceContractNames.feed,
      handler: onFeed,
      requestCodec: ParlanceContractCodecs.codecWireFeedRequest,
      responseCodec: ParlanceContractCodecs.codecWireFeedItem,
    );
    addUnaryMethod<WireCallRequest, WireCallReply>(
      methodName: ParlanceContractNames.invoke,
      handler: onInvoke,
      requestCodec: ParlanceContractCodecs.codecWireCallRequest,
      responseCodec: ParlanceContractCodecs.codecWireCallReply,
    );
    addUnaryMethod<WireWhyRequest, WireJson>(
      methodName: ParlanceContractNames.why,
      handler: onWhy,
      requestCodec: ParlanceContractCodecs.codecWireWhyRequest,
      responseCodec: ParlanceContractCodecs.codecWireJson,
    );
    addUnaryMethod<WireRecentRequest, WireJson>(
      methodName: ParlanceContractNames.recent,
      handler: onRecent,
      requestCodec: ParlanceContractCodecs.codecWireRecentRequest,
      responseCodec: ParlanceContractCodecs.codecWireJson,
    );
    addUnaryMethod<WireSubscribe, WireJson>(
      methodName: ParlanceContractNames.subscribe,
      handler: onSubscribe,
      requestCodec: ParlanceContractCodecs.codecWireSubscribe,
      responseCodec: ParlanceContractCodecs.codecWireJson,
    );
    addUnaryMethod<WireDefine, RpcNull>(
      methodName: ParlanceContractNames.define,
      handler: onDefine,
      requestCodec: ParlanceContractCodecs.codecWireDefine,
      responseCodec: ParlanceContractCodecs.codecRpcNull,
    );
    addUnaryMethod<WireName, RpcNull>(
      methodName: ParlanceContractNames.undefine,
      handler: onUndefine,
      requestCodec: ParlanceContractCodecs.codecWireName,
      responseCodec: ParlanceContractCodecs.codecRpcNull,
    );
    addUnaryMethod<WireSet, RpcNull>(
      methodName: ParlanceContractNames.write,
      handler: onWrite,
      requestCodec: ParlanceContractCodecs.codecWireSet,
      responseCodec: ParlanceContractCodecs.codecRpcNull,
    );
    addUnaryMethod<WireEmit, WireTaken>(
      methodName: ParlanceContractNames.emit,
      handler: onEmit,
      requestCodec: ParlanceContractCodecs.codecWireEmit,
      responseCodec: ParlanceContractCodecs.codecWireTaken,
    );
    addUnaryMethod<WireJson, WireJson>(
      methodName: ParlanceContractNames.apply,
      handler: onApply,
      requestCodec: ParlanceContractCodecs.codecWireJson,
      responseCodec: ParlanceContractCodecs.codecWireJson,
    );
  }

  @override
  Future<WireDescription> describe(RpcNull request, {RpcContext? context}) {
    return callUnary<RpcNull, WireDescription>(
      methodName: ParlanceContractNames.describe,
      requestCodec: ParlanceContractCodecs.codecRpcNull,
      responseCodec: ParlanceContractCodecs.codecWireDescription,
      request: request,
      context: context,
    );
  }

  @override
  Stream<WireFeedItem> feed(WireFeedRequest request, {RpcContext? context}) {
    return callServerStream<WireFeedRequest, WireFeedItem>(
      methodName: ParlanceContractNames.feed,
      requestCodec: ParlanceContractCodecs.codecWireFeedRequest,
      responseCodec: ParlanceContractCodecs.codecWireFeedItem,
      request: request,
      context: context,
    );
  }

  @override
  Future<WireCallReply> invoke(WireCallRequest request, {RpcContext? context}) {
    return callUnary<WireCallRequest, WireCallReply>(
      methodName: ParlanceContractNames.invoke,
      requestCodec: ParlanceContractCodecs.codecWireCallRequest,
      responseCodec: ParlanceContractCodecs.codecWireCallReply,
      request: request,
      context: context,
    );
  }

  @override
  Future<WireJson> why(WireWhyRequest request, {RpcContext? context}) {
    return callUnary<WireWhyRequest, WireJson>(
      methodName: ParlanceContractNames.why,
      requestCodec: ParlanceContractCodecs.codecWireWhyRequest,
      responseCodec: ParlanceContractCodecs.codecWireJson,
      request: request,
      context: context,
    );
  }

  @override
  Future<WireJson> recent(WireRecentRequest request, {RpcContext? context}) {
    return callUnary<WireRecentRequest, WireJson>(
      methodName: ParlanceContractNames.recent,
      requestCodec: ParlanceContractCodecs.codecWireRecentRequest,
      responseCodec: ParlanceContractCodecs.codecWireJson,
      request: request,
      context: context,
    );
  }

  @override
  Future<WireJson> subscribe(WireSubscribe request, {RpcContext? context}) {
    return callUnary<WireSubscribe, WireJson>(
      methodName: ParlanceContractNames.subscribe,
      requestCodec: ParlanceContractCodecs.codecWireSubscribe,
      responseCodec: ParlanceContractCodecs.codecWireJson,
      request: request,
      context: context,
    );
  }

  @override
  Future<RpcNull> define(WireDefine request, {RpcContext? context}) {
    return callUnary<WireDefine, RpcNull>(
      methodName: ParlanceContractNames.define,
      requestCodec: ParlanceContractCodecs.codecWireDefine,
      responseCodec: ParlanceContractCodecs.codecRpcNull,
      request: request,
      context: context,
    );
  }

  @override
  Future<RpcNull> undefine(WireName request, {RpcContext? context}) {
    return callUnary<WireName, RpcNull>(
      methodName: ParlanceContractNames.undefine,
      requestCodec: ParlanceContractCodecs.codecWireName,
      responseCodec: ParlanceContractCodecs.codecRpcNull,
      request: request,
      context: context,
    );
  }

  @override
  Future<RpcNull> write(WireSet request, {RpcContext? context}) {
    return callUnary<WireSet, RpcNull>(
      methodName: ParlanceContractNames.write,
      requestCodec: ParlanceContractCodecs.codecWireSet,
      responseCodec: ParlanceContractCodecs.codecRpcNull,
      request: request,
      context: context,
    );
  }

  @override
  Future<WireTaken> emit(WireEmit request, {RpcContext? context}) {
    return callUnary<WireEmit, WireTaken>(
      methodName: ParlanceContractNames.emit,
      requestCodec: ParlanceContractCodecs.codecWireEmit,
      responseCodec: ParlanceContractCodecs.codecWireTaken,
      request: request,
      context: context,
    );
  }

  @override
  Future<WireJson> apply(WireJson request, {RpcContext? context}) {
    return callUnary<WireJson, WireJson>(
      methodName: ParlanceContractNames.apply,
      requestCodec: ParlanceContractCodecs.codecWireJson,
      responseCodec: ParlanceContractCodecs.codecWireJson,
      request: request,
      context: context,
    );
  }

  Future<WireDescription> onDescribe(RpcNull request, {RpcContext? context});

  Stream<WireFeedItem> onFeed(WireFeedRequest request, {RpcContext? context});

  Future<WireCallReply> onInvoke(
    WireCallRequest request, {
    RpcContext? context,
  });

  Future<WireJson> onWhy(WireWhyRequest request, {RpcContext? context});

  Future<WireJson> onRecent(WireRecentRequest request, {RpcContext? context});

  Future<WireJson> onSubscribe(WireSubscribe request, {RpcContext? context});

  Future<RpcNull> onDefine(WireDefine request, {RpcContext? context});

  Future<RpcNull> onUndefine(WireName request, {RpcContext? context});

  Future<RpcNull> onWrite(WireSet request, {RpcContext? context});

  Future<WireTaken> onEmit(WireEmit request, {RpcContext? context});

  Future<WireJson> onApply(WireJson request, {RpcContext? context});
}

class ParlanceContractPeerCaller extends RpcPeerContract
    implements IParlanceContract {
  ParlanceContractPeerCaller(
    RpcPeerEndpoint endpoint, {
    String? serviceNameOverride,
    RpcDataTransferMode dataTransferMode = RpcDataTransferMode.auto,
  }) : super(
         serviceNameOverride ?? ParlanceContractNames.service,
         endpoint,
         dataTransferMode: dataTransferMode,
         callerDataTransferMode: dataTransferMode,
       );

  @override
  void setup() {}

  @override
  Future<WireDescription> describe(RpcNull request, {RpcContext? context}) {
    return callUnary<RpcNull, WireDescription>(
      methodName: ParlanceContractNames.describe,
      requestCodec: ParlanceContractCodecs.codecRpcNull,
      responseCodec: ParlanceContractCodecs.codecWireDescription,
      request: request,
      context: context,
    );
  }

  @override
  Stream<WireFeedItem> feed(WireFeedRequest request, {RpcContext? context}) {
    return callServerStream<WireFeedRequest, WireFeedItem>(
      methodName: ParlanceContractNames.feed,
      requestCodec: ParlanceContractCodecs.codecWireFeedRequest,
      responseCodec: ParlanceContractCodecs.codecWireFeedItem,
      request: request,
      context: context,
    );
  }

  @override
  Future<WireCallReply> invoke(WireCallRequest request, {RpcContext? context}) {
    return callUnary<WireCallRequest, WireCallReply>(
      methodName: ParlanceContractNames.invoke,
      requestCodec: ParlanceContractCodecs.codecWireCallRequest,
      responseCodec: ParlanceContractCodecs.codecWireCallReply,
      request: request,
      context: context,
    );
  }

  @override
  Future<WireJson> why(WireWhyRequest request, {RpcContext? context}) {
    return callUnary<WireWhyRequest, WireJson>(
      methodName: ParlanceContractNames.why,
      requestCodec: ParlanceContractCodecs.codecWireWhyRequest,
      responseCodec: ParlanceContractCodecs.codecWireJson,
      request: request,
      context: context,
    );
  }

  @override
  Future<WireJson> recent(WireRecentRequest request, {RpcContext? context}) {
    return callUnary<WireRecentRequest, WireJson>(
      methodName: ParlanceContractNames.recent,
      requestCodec: ParlanceContractCodecs.codecWireRecentRequest,
      responseCodec: ParlanceContractCodecs.codecWireJson,
      request: request,
      context: context,
    );
  }

  @override
  Future<WireJson> subscribe(WireSubscribe request, {RpcContext? context}) {
    return callUnary<WireSubscribe, WireJson>(
      methodName: ParlanceContractNames.subscribe,
      requestCodec: ParlanceContractCodecs.codecWireSubscribe,
      responseCodec: ParlanceContractCodecs.codecWireJson,
      request: request,
      context: context,
    );
  }

  @override
  Future<RpcNull> define(WireDefine request, {RpcContext? context}) {
    return callUnary<WireDefine, RpcNull>(
      methodName: ParlanceContractNames.define,
      requestCodec: ParlanceContractCodecs.codecWireDefine,
      responseCodec: ParlanceContractCodecs.codecRpcNull,
      request: request,
      context: context,
    );
  }

  @override
  Future<RpcNull> undefine(WireName request, {RpcContext? context}) {
    return callUnary<WireName, RpcNull>(
      methodName: ParlanceContractNames.undefine,
      requestCodec: ParlanceContractCodecs.codecWireName,
      responseCodec: ParlanceContractCodecs.codecRpcNull,
      request: request,
      context: context,
    );
  }

  @override
  Future<RpcNull> write(WireSet request, {RpcContext? context}) {
    return callUnary<WireSet, RpcNull>(
      methodName: ParlanceContractNames.write,
      requestCodec: ParlanceContractCodecs.codecWireSet,
      responseCodec: ParlanceContractCodecs.codecRpcNull,
      request: request,
      context: context,
    );
  }

  @override
  Future<WireTaken> emit(WireEmit request, {RpcContext? context}) {
    return callUnary<WireEmit, WireTaken>(
      methodName: ParlanceContractNames.emit,
      requestCodec: ParlanceContractCodecs.codecWireEmit,
      responseCodec: ParlanceContractCodecs.codecWireTaken,
      request: request,
      context: context,
    );
  }

  @override
  Future<WireJson> apply(WireJson request, {RpcContext? context}) {
    return callUnary<WireJson, WireJson>(
      methodName: ParlanceContractNames.apply,
      requestCodec: ParlanceContractCodecs.codecWireJson,
      responseCodec: ParlanceContractCodecs.codecWireJson,
      request: request,
      context: context,
    );
  }
}

// ignore_for_file: type=lint, unused_element

class ParlanceOwnerContractNames {
  const ParlanceOwnerContractNames._();
  static const service = 'ParlanceOwner';
  static String instance(String suffix) => '$service\_$suffix';
  static const serve = 'serve';
  static const judge = 'judge';
}

class ParlanceOwnerContractCodecs {
  const ParlanceOwnerContractCodecs._();
  static const codecWireJson = RpcCodec<WireJson>(WireJson.fromJson);
  static const codecWireServe = RpcCodec<WireServe>(WireServe.fromJson);
  static const codecWireServed = RpcCodec<WireServed>(WireServed.fromJson);
}

abstract class ParlanceOwnerContractPeer extends RpcPeerContract
    implements IParlanceOwnerContract {
  ParlanceOwnerContractPeer(
    RpcPeerEndpoint endpoint, {
    String? serviceNameOverride,
    RpcDataTransferMode dataTransferMode = RpcDataTransferMode.auto,
  }) : super(
         serviceNameOverride ?? ParlanceOwnerContractNames.service,
         endpoint,
         dataTransferMode: dataTransferMode,
         callerDataTransferMode: dataTransferMode,
       );

  @override
  void setup() {
    addUnaryMethod<WireServe, WireServed>(
      methodName: ParlanceOwnerContractNames.serve,
      handler: onServe,
      requestCodec: ParlanceOwnerContractCodecs.codecWireServe,
      responseCodec: ParlanceOwnerContractCodecs.codecWireServed,
    );
    addUnaryMethod<WireJson, WireJson>(
      methodName: ParlanceOwnerContractNames.judge,
      handler: onJudge,
      requestCodec: ParlanceOwnerContractCodecs.codecWireJson,
      responseCodec: ParlanceOwnerContractCodecs.codecWireJson,
    );
  }

  @override
  Future<WireServed> serve(WireServe request, {RpcContext? context}) {
    return callUnary<WireServe, WireServed>(
      methodName: ParlanceOwnerContractNames.serve,
      requestCodec: ParlanceOwnerContractCodecs.codecWireServe,
      responseCodec: ParlanceOwnerContractCodecs.codecWireServed,
      request: request,
      context: context,
    );
  }

  @override
  Future<WireJson> judge(WireJson request, {RpcContext? context}) {
    return callUnary<WireJson, WireJson>(
      methodName: ParlanceOwnerContractNames.judge,
      requestCodec: ParlanceOwnerContractCodecs.codecWireJson,
      responseCodec: ParlanceOwnerContractCodecs.codecWireJson,
      request: request,
      context: context,
    );
  }

  Future<WireServed> onServe(WireServe request, {RpcContext? context});

  Future<WireJson> onJudge(WireJson request, {RpcContext? context});
}

class ParlanceOwnerContractPeerCaller extends RpcPeerContract
    implements IParlanceOwnerContract {
  ParlanceOwnerContractPeerCaller(
    RpcPeerEndpoint endpoint, {
    String? serviceNameOverride,
    RpcDataTransferMode dataTransferMode = RpcDataTransferMode.auto,
  }) : super(
         serviceNameOverride ?? ParlanceOwnerContractNames.service,
         endpoint,
         dataTransferMode: dataTransferMode,
         callerDataTransferMode: dataTransferMode,
       );

  @override
  void setup() {}

  @override
  Future<WireServed> serve(WireServe request, {RpcContext? context}) {
    return callUnary<WireServe, WireServed>(
      methodName: ParlanceOwnerContractNames.serve,
      requestCodec: ParlanceOwnerContractCodecs.codecWireServe,
      responseCodec: ParlanceOwnerContractCodecs.codecWireServed,
      request: request,
      context: context,
    );
  }

  @override
  Future<WireJson> judge(WireJson request, {RpcContext? context}) {
    return callUnary<WireJson, WireJson>(
      methodName: ParlanceOwnerContractNames.judge,
      requestCodec: ParlanceOwnerContractCodecs.codecWireJson,
      responseCodec: ParlanceOwnerContractCodecs.codecWireJson,
      request: request,
      context: context,
    );
  }
}
