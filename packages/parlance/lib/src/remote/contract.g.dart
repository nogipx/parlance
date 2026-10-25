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
  static const pushLayer = 'pushLayer';
  static const popLayer = 'popLayer';
  static const layerEvents = 'layerEvents';
  static const why = 'why';
  static const layers = 'layers';
  static const recent = 'recent';
  static const subscribe = 'subscribe';
  static const define = 'define';
  static const undefine = 'undefine';
  static const write = 'set';
  static const emit = 'emit';
}

class ParlanceContractCodecs {
  const ParlanceContractCodecs._();
  static const codecRpcNull = RpcCodec<RpcNull>(RpcNull.fromJson);
  static const codecSbCallReply = RpcCodec<SbCallReply>(SbCallReply.fromJson);
  static const codecSbCallRequest = RpcCodec<SbCallRequest>(
    SbCallRequest.fromJson,
  );
  static const codecSbDefine = RpcCodec<SbDefine>(SbDefine.fromJson);
  static const codecSbDescription = RpcCodec<SbDescription>(
    SbDescription.fromJson,
  );
  static const codecSbEmit = RpcCodec<SbEmit>(SbEmit.fromJson);
  static const codecSbFeedItem = RpcCodec<SbFeedItem>(SbFeedItem.fromJson);
  static const codecSbFeedRequest = RpcCodec<SbFeedRequest>(
    SbFeedRequest.fromJson,
  );
  static const codecSbJson = RpcCodec<SbJson>(SbJson.fromJson);
  static const codecSbLayerEvent = RpcCodec<SbLayerEvent>(
    SbLayerEvent.fromJson,
  );
  static const codecSbLayerRef = RpcCodec<SbLayerRef>(SbLayerRef.fromJson);
  static const codecSbLayerRequest = RpcCodec<SbLayerRequest>(
    SbLayerRequest.fromJson,
  );
  static const codecSbName = RpcCodec<SbName>(SbName.fromJson);
  static const codecSbRecentRequest = RpcCodec<SbRecentRequest>(
    SbRecentRequest.fromJson,
  );
  static const codecSbSet = RpcCodec<SbSet>(SbSet.fromJson);
  static const codecSbSubscribe = RpcCodec<SbSubscribe>(SbSubscribe.fromJson);
  static const codecSbTaken = RpcCodec<SbTaken>(SbTaken.fromJson);
  static const codecSbWhyRequest = RpcCodec<SbWhyRequest>(
    SbWhyRequest.fromJson,
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
    addUnaryMethod<RpcNull, SbDescription>(
      methodName: ParlanceContractNames.describe,
      handler: onDescribe,
      requestCodec: ParlanceContractCodecs.codecRpcNull,
      responseCodec: ParlanceContractCodecs.codecSbDescription,
    );
    addServerStreamMethod<SbFeedRequest, SbFeedItem>(
      methodName: ParlanceContractNames.feed,
      handler: onFeed,
      requestCodec: ParlanceContractCodecs.codecSbFeedRequest,
      responseCodec: ParlanceContractCodecs.codecSbFeedItem,
    );
    addUnaryMethod<SbCallRequest, SbCallReply>(
      methodName: ParlanceContractNames.invoke,
      handler: onInvoke,
      requestCodec: ParlanceContractCodecs.codecSbCallRequest,
      responseCodec: ParlanceContractCodecs.codecSbCallReply,
    );
    addUnaryMethod<SbLayerRequest, SbLayerRef>(
      methodName: ParlanceContractNames.pushLayer,
      handler: onPushLayer,
      requestCodec: ParlanceContractCodecs.codecSbLayerRequest,
      responseCodec: ParlanceContractCodecs.codecSbLayerRef,
    );
    addUnaryMethod<SbLayerRef, RpcNull>(
      methodName: ParlanceContractNames.popLayer,
      handler: onPopLayer,
      requestCodec: ParlanceContractCodecs.codecSbLayerRef,
      responseCodec: ParlanceContractCodecs.codecRpcNull,
    );
    addServerStreamMethod<RpcNull, SbLayerEvent>(
      methodName: ParlanceContractNames.layerEvents,
      handler: onLayerEvents,
      requestCodec: ParlanceContractCodecs.codecRpcNull,
      responseCodec: ParlanceContractCodecs.codecSbLayerEvent,
    );
    addUnaryMethod<SbWhyRequest, SbJson>(
      methodName: ParlanceContractNames.why,
      handler: onWhy,
      requestCodec: ParlanceContractCodecs.codecSbWhyRequest,
      responseCodec: ParlanceContractCodecs.codecSbJson,
    );
    addUnaryMethod<RpcNull, SbJson>(
      methodName: ParlanceContractNames.layers,
      handler: onLayers,
      requestCodec: ParlanceContractCodecs.codecRpcNull,
      responseCodec: ParlanceContractCodecs.codecSbJson,
    );
    addUnaryMethod<SbRecentRequest, SbJson>(
      methodName: ParlanceContractNames.recent,
      handler: onRecent,
      requestCodec: ParlanceContractCodecs.codecSbRecentRequest,
      responseCodec: ParlanceContractCodecs.codecSbJson,
    );
    addUnaryMethod<SbSubscribe, SbJson>(
      methodName: ParlanceContractNames.subscribe,
      handler: onSubscribe,
      requestCodec: ParlanceContractCodecs.codecSbSubscribe,
      responseCodec: ParlanceContractCodecs.codecSbJson,
    );
    addUnaryMethod<SbDefine, RpcNull>(
      methodName: ParlanceContractNames.define,
      handler: onDefine,
      requestCodec: ParlanceContractCodecs.codecSbDefine,
      responseCodec: ParlanceContractCodecs.codecRpcNull,
    );
    addUnaryMethod<SbName, RpcNull>(
      methodName: ParlanceContractNames.undefine,
      handler: onUndefine,
      requestCodec: ParlanceContractCodecs.codecSbName,
      responseCodec: ParlanceContractCodecs.codecRpcNull,
    );
    addUnaryMethod<SbSet, RpcNull>(
      methodName: ParlanceContractNames.write,
      handler: onWrite,
      requestCodec: ParlanceContractCodecs.codecSbSet,
      responseCodec: ParlanceContractCodecs.codecRpcNull,
    );
    addUnaryMethod<SbEmit, SbTaken>(
      methodName: ParlanceContractNames.emit,
      handler: onEmit,
      requestCodec: ParlanceContractCodecs.codecSbEmit,
      responseCodec: ParlanceContractCodecs.codecSbTaken,
    );
  }

  @override
  Future<SbDescription> describe(RpcNull request, {RpcContext? context}) {
    return callUnary<RpcNull, SbDescription>(
      methodName: ParlanceContractNames.describe,
      requestCodec: ParlanceContractCodecs.codecRpcNull,
      responseCodec: ParlanceContractCodecs.codecSbDescription,
      request: request,
      context: context,
    );
  }

  @override
  Stream<SbFeedItem> feed(SbFeedRequest request, {RpcContext? context}) {
    return callServerStream<SbFeedRequest, SbFeedItem>(
      methodName: ParlanceContractNames.feed,
      requestCodec: ParlanceContractCodecs.codecSbFeedRequest,
      responseCodec: ParlanceContractCodecs.codecSbFeedItem,
      request: request,
      context: context,
    );
  }

  @override
  Future<SbCallReply> invoke(SbCallRequest request, {RpcContext? context}) {
    return callUnary<SbCallRequest, SbCallReply>(
      methodName: ParlanceContractNames.invoke,
      requestCodec: ParlanceContractCodecs.codecSbCallRequest,
      responseCodec: ParlanceContractCodecs.codecSbCallReply,
      request: request,
      context: context,
    );
  }

  @override
  Future<SbLayerRef> pushLayer(SbLayerRequest request, {RpcContext? context}) {
    return callUnary<SbLayerRequest, SbLayerRef>(
      methodName: ParlanceContractNames.pushLayer,
      requestCodec: ParlanceContractCodecs.codecSbLayerRequest,
      responseCodec: ParlanceContractCodecs.codecSbLayerRef,
      request: request,
      context: context,
    );
  }

  @override
  Future<RpcNull> popLayer(SbLayerRef request, {RpcContext? context}) {
    return callUnary<SbLayerRef, RpcNull>(
      methodName: ParlanceContractNames.popLayer,
      requestCodec: ParlanceContractCodecs.codecSbLayerRef,
      responseCodec: ParlanceContractCodecs.codecRpcNull,
      request: request,
      context: context,
    );
  }

  @override
  Stream<SbLayerEvent> layerEvents(RpcNull request, {RpcContext? context}) {
    return callServerStream<RpcNull, SbLayerEvent>(
      methodName: ParlanceContractNames.layerEvents,
      requestCodec: ParlanceContractCodecs.codecRpcNull,
      responseCodec: ParlanceContractCodecs.codecSbLayerEvent,
      request: request,
      context: context,
    );
  }

  @override
  Future<SbJson> why(SbWhyRequest request, {RpcContext? context}) {
    return callUnary<SbWhyRequest, SbJson>(
      methodName: ParlanceContractNames.why,
      requestCodec: ParlanceContractCodecs.codecSbWhyRequest,
      responseCodec: ParlanceContractCodecs.codecSbJson,
      request: request,
      context: context,
    );
  }

  @override
  Future<SbJson> layers(RpcNull request, {RpcContext? context}) {
    return callUnary<RpcNull, SbJson>(
      methodName: ParlanceContractNames.layers,
      requestCodec: ParlanceContractCodecs.codecRpcNull,
      responseCodec: ParlanceContractCodecs.codecSbJson,
      request: request,
      context: context,
    );
  }

  @override
  Future<SbJson> recent(SbRecentRequest request, {RpcContext? context}) {
    return callUnary<SbRecentRequest, SbJson>(
      methodName: ParlanceContractNames.recent,
      requestCodec: ParlanceContractCodecs.codecSbRecentRequest,
      responseCodec: ParlanceContractCodecs.codecSbJson,
      request: request,
      context: context,
    );
  }

  @override
  Future<SbJson> subscribe(SbSubscribe request, {RpcContext? context}) {
    return callUnary<SbSubscribe, SbJson>(
      methodName: ParlanceContractNames.subscribe,
      requestCodec: ParlanceContractCodecs.codecSbSubscribe,
      responseCodec: ParlanceContractCodecs.codecSbJson,
      request: request,
      context: context,
    );
  }

  @override
  Future<RpcNull> define(SbDefine request, {RpcContext? context}) {
    return callUnary<SbDefine, RpcNull>(
      methodName: ParlanceContractNames.define,
      requestCodec: ParlanceContractCodecs.codecSbDefine,
      responseCodec: ParlanceContractCodecs.codecRpcNull,
      request: request,
      context: context,
    );
  }

  @override
  Future<RpcNull> undefine(SbName request, {RpcContext? context}) {
    return callUnary<SbName, RpcNull>(
      methodName: ParlanceContractNames.undefine,
      requestCodec: ParlanceContractCodecs.codecSbName,
      responseCodec: ParlanceContractCodecs.codecRpcNull,
      request: request,
      context: context,
    );
  }

  @override
  Future<RpcNull> write(SbSet request, {RpcContext? context}) {
    return callUnary<SbSet, RpcNull>(
      methodName: ParlanceContractNames.write,
      requestCodec: ParlanceContractCodecs.codecSbSet,
      responseCodec: ParlanceContractCodecs.codecRpcNull,
      request: request,
      context: context,
    );
  }

  @override
  Future<SbTaken> emit(SbEmit request, {RpcContext? context}) {
    return callUnary<SbEmit, SbTaken>(
      methodName: ParlanceContractNames.emit,
      requestCodec: ParlanceContractCodecs.codecSbEmit,
      responseCodec: ParlanceContractCodecs.codecSbTaken,
      request: request,
      context: context,
    );
  }

  Future<SbDescription> onDescribe(RpcNull request, {RpcContext? context});

  Stream<SbFeedItem> onFeed(SbFeedRequest request, {RpcContext? context});

  Future<SbCallReply> onInvoke(SbCallRequest request, {RpcContext? context});

  Future<SbLayerRef> onPushLayer(SbLayerRequest request, {RpcContext? context});

  Future<RpcNull> onPopLayer(SbLayerRef request, {RpcContext? context});

  Stream<SbLayerEvent> onLayerEvents(RpcNull request, {RpcContext? context});

  Future<SbJson> onWhy(SbWhyRequest request, {RpcContext? context});

  Future<SbJson> onLayers(RpcNull request, {RpcContext? context});

  Future<SbJson> onRecent(SbRecentRequest request, {RpcContext? context});

  Future<SbJson> onSubscribe(SbSubscribe request, {RpcContext? context});

  Future<RpcNull> onDefine(SbDefine request, {RpcContext? context});

  Future<RpcNull> onUndefine(SbName request, {RpcContext? context});

  Future<RpcNull> onWrite(SbSet request, {RpcContext? context});

  Future<SbTaken> onEmit(SbEmit request, {RpcContext? context});
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
  Future<SbDescription> describe(RpcNull request, {RpcContext? context}) {
    return callUnary<RpcNull, SbDescription>(
      methodName: ParlanceContractNames.describe,
      requestCodec: ParlanceContractCodecs.codecRpcNull,
      responseCodec: ParlanceContractCodecs.codecSbDescription,
      request: request,
      context: context,
    );
  }

  @override
  Stream<SbFeedItem> feed(SbFeedRequest request, {RpcContext? context}) {
    return callServerStream<SbFeedRequest, SbFeedItem>(
      methodName: ParlanceContractNames.feed,
      requestCodec: ParlanceContractCodecs.codecSbFeedRequest,
      responseCodec: ParlanceContractCodecs.codecSbFeedItem,
      request: request,
      context: context,
    );
  }

  @override
  Future<SbCallReply> invoke(SbCallRequest request, {RpcContext? context}) {
    return callUnary<SbCallRequest, SbCallReply>(
      methodName: ParlanceContractNames.invoke,
      requestCodec: ParlanceContractCodecs.codecSbCallRequest,
      responseCodec: ParlanceContractCodecs.codecSbCallReply,
      request: request,
      context: context,
    );
  }

  @override
  Future<SbLayerRef> pushLayer(SbLayerRequest request, {RpcContext? context}) {
    return callUnary<SbLayerRequest, SbLayerRef>(
      methodName: ParlanceContractNames.pushLayer,
      requestCodec: ParlanceContractCodecs.codecSbLayerRequest,
      responseCodec: ParlanceContractCodecs.codecSbLayerRef,
      request: request,
      context: context,
    );
  }

  @override
  Future<RpcNull> popLayer(SbLayerRef request, {RpcContext? context}) {
    return callUnary<SbLayerRef, RpcNull>(
      methodName: ParlanceContractNames.popLayer,
      requestCodec: ParlanceContractCodecs.codecSbLayerRef,
      responseCodec: ParlanceContractCodecs.codecRpcNull,
      request: request,
      context: context,
    );
  }

  @override
  Stream<SbLayerEvent> layerEvents(RpcNull request, {RpcContext? context}) {
    return callServerStream<RpcNull, SbLayerEvent>(
      methodName: ParlanceContractNames.layerEvents,
      requestCodec: ParlanceContractCodecs.codecRpcNull,
      responseCodec: ParlanceContractCodecs.codecSbLayerEvent,
      request: request,
      context: context,
    );
  }

  @override
  Future<SbJson> why(SbWhyRequest request, {RpcContext? context}) {
    return callUnary<SbWhyRequest, SbJson>(
      methodName: ParlanceContractNames.why,
      requestCodec: ParlanceContractCodecs.codecSbWhyRequest,
      responseCodec: ParlanceContractCodecs.codecSbJson,
      request: request,
      context: context,
    );
  }

  @override
  Future<SbJson> layers(RpcNull request, {RpcContext? context}) {
    return callUnary<RpcNull, SbJson>(
      methodName: ParlanceContractNames.layers,
      requestCodec: ParlanceContractCodecs.codecRpcNull,
      responseCodec: ParlanceContractCodecs.codecSbJson,
      request: request,
      context: context,
    );
  }

  @override
  Future<SbJson> recent(SbRecentRequest request, {RpcContext? context}) {
    return callUnary<SbRecentRequest, SbJson>(
      methodName: ParlanceContractNames.recent,
      requestCodec: ParlanceContractCodecs.codecSbRecentRequest,
      responseCodec: ParlanceContractCodecs.codecSbJson,
      request: request,
      context: context,
    );
  }

  @override
  Future<SbJson> subscribe(SbSubscribe request, {RpcContext? context}) {
    return callUnary<SbSubscribe, SbJson>(
      methodName: ParlanceContractNames.subscribe,
      requestCodec: ParlanceContractCodecs.codecSbSubscribe,
      responseCodec: ParlanceContractCodecs.codecSbJson,
      request: request,
      context: context,
    );
  }

  @override
  Future<RpcNull> define(SbDefine request, {RpcContext? context}) {
    return callUnary<SbDefine, RpcNull>(
      methodName: ParlanceContractNames.define,
      requestCodec: ParlanceContractCodecs.codecSbDefine,
      responseCodec: ParlanceContractCodecs.codecRpcNull,
      request: request,
      context: context,
    );
  }

  @override
  Future<RpcNull> undefine(SbName request, {RpcContext? context}) {
    return callUnary<SbName, RpcNull>(
      methodName: ParlanceContractNames.undefine,
      requestCodec: ParlanceContractCodecs.codecSbName,
      responseCodec: ParlanceContractCodecs.codecRpcNull,
      request: request,
      context: context,
    );
  }

  @override
  Future<RpcNull> write(SbSet request, {RpcContext? context}) {
    return callUnary<SbSet, RpcNull>(
      methodName: ParlanceContractNames.write,
      requestCodec: ParlanceContractCodecs.codecSbSet,
      responseCodec: ParlanceContractCodecs.codecRpcNull,
      request: request,
      context: context,
    );
  }

  @override
  Future<SbTaken> emit(SbEmit request, {RpcContext? context}) {
    return callUnary<SbEmit, SbTaken>(
      methodName: ParlanceContractNames.emit,
      requestCodec: ParlanceContractCodecs.codecSbEmit,
      responseCodec: ParlanceContractCodecs.codecSbTaken,
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
}

class ParlanceOwnerContractCodecs {
  const ParlanceOwnerContractCodecs._();
  static const codecSbServe = RpcCodec<SbServe>(SbServe.fromJson);
  static const codecSbServed = RpcCodec<SbServed>(SbServed.fromJson);
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
    addUnaryMethod<SbServe, SbServed>(
      methodName: ParlanceOwnerContractNames.serve,
      handler: onServe,
      requestCodec: ParlanceOwnerContractCodecs.codecSbServe,
      responseCodec: ParlanceOwnerContractCodecs.codecSbServed,
    );
  }

  @override
  Future<SbServed> serve(SbServe request, {RpcContext? context}) {
    return callUnary<SbServe, SbServed>(
      methodName: ParlanceOwnerContractNames.serve,
      requestCodec: ParlanceOwnerContractCodecs.codecSbServe,
      responseCodec: ParlanceOwnerContractCodecs.codecSbServed,
      request: request,
      context: context,
    );
  }

  Future<SbServed> onServe(SbServe request, {RpcContext? context});
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
  Future<SbServed> serve(SbServe request, {RpcContext? context}) {
    return callUnary<SbServe, SbServed>(
      methodName: ParlanceOwnerContractNames.serve,
      requestCodec: ParlanceOwnerContractCodecs.codecSbServe,
      responseCodec: ParlanceOwnerContractCodecs.codecSbServed,
      request: request,
      context: context,
    );
  }
}
