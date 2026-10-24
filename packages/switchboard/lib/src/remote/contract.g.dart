// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'contract.dart';

// **************************************************************************
// RpcDartGenerator
// **************************************************************************

// ignore_for_file: type=lint, unused_element

class SwitchboardContractNames {
  const SwitchboardContractNames._();
  static const service = 'Switchboard';
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

class SwitchboardContractCodecs {
  const SwitchboardContractCodecs._();
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

abstract class SwitchboardContractPeer extends RpcPeerContract
    implements ISwitchboardContract {
  SwitchboardContractPeer(
    RpcPeerEndpoint endpoint, {
    String? serviceNameOverride,
    RpcDataTransferMode dataTransferMode = RpcDataTransferMode.auto,
  }) : super(
         serviceNameOverride ?? SwitchboardContractNames.service,
         endpoint,
         dataTransferMode: dataTransferMode,
         callerDataTransferMode: dataTransferMode,
       );

  @override
  void setup() {
    addUnaryMethod<RpcNull, SbDescription>(
      methodName: SwitchboardContractNames.describe,
      handler: onDescribe,
      requestCodec: SwitchboardContractCodecs.codecRpcNull,
      responseCodec: SwitchboardContractCodecs.codecSbDescription,
    );
    addServerStreamMethod<SbFeedRequest, SbFeedItem>(
      methodName: SwitchboardContractNames.feed,
      handler: onFeed,
      requestCodec: SwitchboardContractCodecs.codecSbFeedRequest,
      responseCodec: SwitchboardContractCodecs.codecSbFeedItem,
    );
    addUnaryMethod<SbCallRequest, SbCallReply>(
      methodName: SwitchboardContractNames.invoke,
      handler: onInvoke,
      requestCodec: SwitchboardContractCodecs.codecSbCallRequest,
      responseCodec: SwitchboardContractCodecs.codecSbCallReply,
    );
    addUnaryMethod<SbLayerRequest, SbLayerRef>(
      methodName: SwitchboardContractNames.pushLayer,
      handler: onPushLayer,
      requestCodec: SwitchboardContractCodecs.codecSbLayerRequest,
      responseCodec: SwitchboardContractCodecs.codecSbLayerRef,
    );
    addUnaryMethod<SbLayerRef, RpcNull>(
      methodName: SwitchboardContractNames.popLayer,
      handler: onPopLayer,
      requestCodec: SwitchboardContractCodecs.codecSbLayerRef,
      responseCodec: SwitchboardContractCodecs.codecRpcNull,
    );
    addServerStreamMethod<RpcNull, SbLayerEvent>(
      methodName: SwitchboardContractNames.layerEvents,
      handler: onLayerEvents,
      requestCodec: SwitchboardContractCodecs.codecRpcNull,
      responseCodec: SwitchboardContractCodecs.codecSbLayerEvent,
    );
    addUnaryMethod<SbWhyRequest, SbJson>(
      methodName: SwitchboardContractNames.why,
      handler: onWhy,
      requestCodec: SwitchboardContractCodecs.codecSbWhyRequest,
      responseCodec: SwitchboardContractCodecs.codecSbJson,
    );
    addUnaryMethod<RpcNull, SbJson>(
      methodName: SwitchboardContractNames.layers,
      handler: onLayers,
      requestCodec: SwitchboardContractCodecs.codecRpcNull,
      responseCodec: SwitchboardContractCodecs.codecSbJson,
    );
    addUnaryMethod<SbRecentRequest, SbJson>(
      methodName: SwitchboardContractNames.recent,
      handler: onRecent,
      requestCodec: SwitchboardContractCodecs.codecSbRecentRequest,
      responseCodec: SwitchboardContractCodecs.codecSbJson,
    );
    addUnaryMethod<SbSubscribe, SbJson>(
      methodName: SwitchboardContractNames.subscribe,
      handler: onSubscribe,
      requestCodec: SwitchboardContractCodecs.codecSbSubscribe,
      responseCodec: SwitchboardContractCodecs.codecSbJson,
    );
    addUnaryMethod<SbDefine, RpcNull>(
      methodName: SwitchboardContractNames.define,
      handler: onDefine,
      requestCodec: SwitchboardContractCodecs.codecSbDefine,
      responseCodec: SwitchboardContractCodecs.codecRpcNull,
    );
    addUnaryMethod<SbName, RpcNull>(
      methodName: SwitchboardContractNames.undefine,
      handler: onUndefine,
      requestCodec: SwitchboardContractCodecs.codecSbName,
      responseCodec: SwitchboardContractCodecs.codecRpcNull,
    );
    addUnaryMethod<SbSet, RpcNull>(
      methodName: SwitchboardContractNames.write,
      handler: onWrite,
      requestCodec: SwitchboardContractCodecs.codecSbSet,
      responseCodec: SwitchboardContractCodecs.codecRpcNull,
    );
    addUnaryMethod<SbEmit, SbTaken>(
      methodName: SwitchboardContractNames.emit,
      handler: onEmit,
      requestCodec: SwitchboardContractCodecs.codecSbEmit,
      responseCodec: SwitchboardContractCodecs.codecSbTaken,
    );
  }

  @override
  Future<SbDescription> describe(RpcNull request, {RpcContext? context}) {
    return callUnary<RpcNull, SbDescription>(
      methodName: SwitchboardContractNames.describe,
      requestCodec: SwitchboardContractCodecs.codecRpcNull,
      responseCodec: SwitchboardContractCodecs.codecSbDescription,
      request: request,
      context: context,
    );
  }

  @override
  Stream<SbFeedItem> feed(SbFeedRequest request, {RpcContext? context}) {
    return callServerStream<SbFeedRequest, SbFeedItem>(
      methodName: SwitchboardContractNames.feed,
      requestCodec: SwitchboardContractCodecs.codecSbFeedRequest,
      responseCodec: SwitchboardContractCodecs.codecSbFeedItem,
      request: request,
      context: context,
    );
  }

  @override
  Future<SbCallReply> invoke(SbCallRequest request, {RpcContext? context}) {
    return callUnary<SbCallRequest, SbCallReply>(
      methodName: SwitchboardContractNames.invoke,
      requestCodec: SwitchboardContractCodecs.codecSbCallRequest,
      responseCodec: SwitchboardContractCodecs.codecSbCallReply,
      request: request,
      context: context,
    );
  }

  @override
  Future<SbLayerRef> pushLayer(SbLayerRequest request, {RpcContext? context}) {
    return callUnary<SbLayerRequest, SbLayerRef>(
      methodName: SwitchboardContractNames.pushLayer,
      requestCodec: SwitchboardContractCodecs.codecSbLayerRequest,
      responseCodec: SwitchboardContractCodecs.codecSbLayerRef,
      request: request,
      context: context,
    );
  }

  @override
  Future<RpcNull> popLayer(SbLayerRef request, {RpcContext? context}) {
    return callUnary<SbLayerRef, RpcNull>(
      methodName: SwitchboardContractNames.popLayer,
      requestCodec: SwitchboardContractCodecs.codecSbLayerRef,
      responseCodec: SwitchboardContractCodecs.codecRpcNull,
      request: request,
      context: context,
    );
  }

  @override
  Stream<SbLayerEvent> layerEvents(RpcNull request, {RpcContext? context}) {
    return callServerStream<RpcNull, SbLayerEvent>(
      methodName: SwitchboardContractNames.layerEvents,
      requestCodec: SwitchboardContractCodecs.codecRpcNull,
      responseCodec: SwitchboardContractCodecs.codecSbLayerEvent,
      request: request,
      context: context,
    );
  }

  @override
  Future<SbJson> why(SbWhyRequest request, {RpcContext? context}) {
    return callUnary<SbWhyRequest, SbJson>(
      methodName: SwitchboardContractNames.why,
      requestCodec: SwitchboardContractCodecs.codecSbWhyRequest,
      responseCodec: SwitchboardContractCodecs.codecSbJson,
      request: request,
      context: context,
    );
  }

  @override
  Future<SbJson> layers(RpcNull request, {RpcContext? context}) {
    return callUnary<RpcNull, SbJson>(
      methodName: SwitchboardContractNames.layers,
      requestCodec: SwitchboardContractCodecs.codecRpcNull,
      responseCodec: SwitchboardContractCodecs.codecSbJson,
      request: request,
      context: context,
    );
  }

  @override
  Future<SbJson> recent(SbRecentRequest request, {RpcContext? context}) {
    return callUnary<SbRecentRequest, SbJson>(
      methodName: SwitchboardContractNames.recent,
      requestCodec: SwitchboardContractCodecs.codecSbRecentRequest,
      responseCodec: SwitchboardContractCodecs.codecSbJson,
      request: request,
      context: context,
    );
  }

  @override
  Future<SbJson> subscribe(SbSubscribe request, {RpcContext? context}) {
    return callUnary<SbSubscribe, SbJson>(
      methodName: SwitchboardContractNames.subscribe,
      requestCodec: SwitchboardContractCodecs.codecSbSubscribe,
      responseCodec: SwitchboardContractCodecs.codecSbJson,
      request: request,
      context: context,
    );
  }

  @override
  Future<RpcNull> define(SbDefine request, {RpcContext? context}) {
    return callUnary<SbDefine, RpcNull>(
      methodName: SwitchboardContractNames.define,
      requestCodec: SwitchboardContractCodecs.codecSbDefine,
      responseCodec: SwitchboardContractCodecs.codecRpcNull,
      request: request,
      context: context,
    );
  }

  @override
  Future<RpcNull> undefine(SbName request, {RpcContext? context}) {
    return callUnary<SbName, RpcNull>(
      methodName: SwitchboardContractNames.undefine,
      requestCodec: SwitchboardContractCodecs.codecSbName,
      responseCodec: SwitchboardContractCodecs.codecRpcNull,
      request: request,
      context: context,
    );
  }

  @override
  Future<RpcNull> write(SbSet request, {RpcContext? context}) {
    return callUnary<SbSet, RpcNull>(
      methodName: SwitchboardContractNames.write,
      requestCodec: SwitchboardContractCodecs.codecSbSet,
      responseCodec: SwitchboardContractCodecs.codecRpcNull,
      request: request,
      context: context,
    );
  }

  @override
  Future<SbTaken> emit(SbEmit request, {RpcContext? context}) {
    return callUnary<SbEmit, SbTaken>(
      methodName: SwitchboardContractNames.emit,
      requestCodec: SwitchboardContractCodecs.codecSbEmit,
      responseCodec: SwitchboardContractCodecs.codecSbTaken,
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

class SwitchboardContractPeerCaller extends RpcPeerContract
    implements ISwitchboardContract {
  SwitchboardContractPeerCaller(
    RpcPeerEndpoint endpoint, {
    String? serviceNameOverride,
    RpcDataTransferMode dataTransferMode = RpcDataTransferMode.auto,
  }) : super(
         serviceNameOverride ?? SwitchboardContractNames.service,
         endpoint,
         dataTransferMode: dataTransferMode,
         callerDataTransferMode: dataTransferMode,
       );

  @override
  void setup() {}

  @override
  Future<SbDescription> describe(RpcNull request, {RpcContext? context}) {
    return callUnary<RpcNull, SbDescription>(
      methodName: SwitchboardContractNames.describe,
      requestCodec: SwitchboardContractCodecs.codecRpcNull,
      responseCodec: SwitchboardContractCodecs.codecSbDescription,
      request: request,
      context: context,
    );
  }

  @override
  Stream<SbFeedItem> feed(SbFeedRequest request, {RpcContext? context}) {
    return callServerStream<SbFeedRequest, SbFeedItem>(
      methodName: SwitchboardContractNames.feed,
      requestCodec: SwitchboardContractCodecs.codecSbFeedRequest,
      responseCodec: SwitchboardContractCodecs.codecSbFeedItem,
      request: request,
      context: context,
    );
  }

  @override
  Future<SbCallReply> invoke(SbCallRequest request, {RpcContext? context}) {
    return callUnary<SbCallRequest, SbCallReply>(
      methodName: SwitchboardContractNames.invoke,
      requestCodec: SwitchboardContractCodecs.codecSbCallRequest,
      responseCodec: SwitchboardContractCodecs.codecSbCallReply,
      request: request,
      context: context,
    );
  }

  @override
  Future<SbLayerRef> pushLayer(SbLayerRequest request, {RpcContext? context}) {
    return callUnary<SbLayerRequest, SbLayerRef>(
      methodName: SwitchboardContractNames.pushLayer,
      requestCodec: SwitchboardContractCodecs.codecSbLayerRequest,
      responseCodec: SwitchboardContractCodecs.codecSbLayerRef,
      request: request,
      context: context,
    );
  }

  @override
  Future<RpcNull> popLayer(SbLayerRef request, {RpcContext? context}) {
    return callUnary<SbLayerRef, RpcNull>(
      methodName: SwitchboardContractNames.popLayer,
      requestCodec: SwitchboardContractCodecs.codecSbLayerRef,
      responseCodec: SwitchboardContractCodecs.codecRpcNull,
      request: request,
      context: context,
    );
  }

  @override
  Stream<SbLayerEvent> layerEvents(RpcNull request, {RpcContext? context}) {
    return callServerStream<RpcNull, SbLayerEvent>(
      methodName: SwitchboardContractNames.layerEvents,
      requestCodec: SwitchboardContractCodecs.codecRpcNull,
      responseCodec: SwitchboardContractCodecs.codecSbLayerEvent,
      request: request,
      context: context,
    );
  }

  @override
  Future<SbJson> why(SbWhyRequest request, {RpcContext? context}) {
    return callUnary<SbWhyRequest, SbJson>(
      methodName: SwitchboardContractNames.why,
      requestCodec: SwitchboardContractCodecs.codecSbWhyRequest,
      responseCodec: SwitchboardContractCodecs.codecSbJson,
      request: request,
      context: context,
    );
  }

  @override
  Future<SbJson> layers(RpcNull request, {RpcContext? context}) {
    return callUnary<RpcNull, SbJson>(
      methodName: SwitchboardContractNames.layers,
      requestCodec: SwitchboardContractCodecs.codecRpcNull,
      responseCodec: SwitchboardContractCodecs.codecSbJson,
      request: request,
      context: context,
    );
  }

  @override
  Future<SbJson> recent(SbRecentRequest request, {RpcContext? context}) {
    return callUnary<SbRecentRequest, SbJson>(
      methodName: SwitchboardContractNames.recent,
      requestCodec: SwitchboardContractCodecs.codecSbRecentRequest,
      responseCodec: SwitchboardContractCodecs.codecSbJson,
      request: request,
      context: context,
    );
  }

  @override
  Future<SbJson> subscribe(SbSubscribe request, {RpcContext? context}) {
    return callUnary<SbSubscribe, SbJson>(
      methodName: SwitchboardContractNames.subscribe,
      requestCodec: SwitchboardContractCodecs.codecSbSubscribe,
      responseCodec: SwitchboardContractCodecs.codecSbJson,
      request: request,
      context: context,
    );
  }

  @override
  Future<RpcNull> define(SbDefine request, {RpcContext? context}) {
    return callUnary<SbDefine, RpcNull>(
      methodName: SwitchboardContractNames.define,
      requestCodec: SwitchboardContractCodecs.codecSbDefine,
      responseCodec: SwitchboardContractCodecs.codecRpcNull,
      request: request,
      context: context,
    );
  }

  @override
  Future<RpcNull> undefine(SbName request, {RpcContext? context}) {
    return callUnary<SbName, RpcNull>(
      methodName: SwitchboardContractNames.undefine,
      requestCodec: SwitchboardContractCodecs.codecSbName,
      responseCodec: SwitchboardContractCodecs.codecRpcNull,
      request: request,
      context: context,
    );
  }

  @override
  Future<RpcNull> write(SbSet request, {RpcContext? context}) {
    return callUnary<SbSet, RpcNull>(
      methodName: SwitchboardContractNames.write,
      requestCodec: SwitchboardContractCodecs.codecSbSet,
      responseCodec: SwitchboardContractCodecs.codecRpcNull,
      request: request,
      context: context,
    );
  }

  @override
  Future<SbTaken> emit(SbEmit request, {RpcContext? context}) {
    return callUnary<SbEmit, SbTaken>(
      methodName: SwitchboardContractNames.emit,
      requestCodec: SwitchboardContractCodecs.codecSbEmit,
      responseCodec: SwitchboardContractCodecs.codecSbTaken,
      request: request,
      context: context,
    );
  }
}

// ignore_for_file: type=lint, unused_element

class SwitchboardOwnerContractNames {
  const SwitchboardOwnerContractNames._();
  static const service = 'SwitchboardOwner';
  static String instance(String suffix) => '$service\_$suffix';
  static const serve = 'serve';
}

class SwitchboardOwnerContractCodecs {
  const SwitchboardOwnerContractCodecs._();
  static const codecSbServe = RpcCodec<SbServe>(SbServe.fromJson);
  static const codecSbServed = RpcCodec<SbServed>(SbServed.fromJson);
}

abstract class SwitchboardOwnerContractPeer extends RpcPeerContract
    implements ISwitchboardOwnerContract {
  SwitchboardOwnerContractPeer(
    RpcPeerEndpoint endpoint, {
    String? serviceNameOverride,
    RpcDataTransferMode dataTransferMode = RpcDataTransferMode.auto,
  }) : super(
         serviceNameOverride ?? SwitchboardOwnerContractNames.service,
         endpoint,
         dataTransferMode: dataTransferMode,
         callerDataTransferMode: dataTransferMode,
       );

  @override
  void setup() {
    addUnaryMethod<SbServe, SbServed>(
      methodName: SwitchboardOwnerContractNames.serve,
      handler: onServe,
      requestCodec: SwitchboardOwnerContractCodecs.codecSbServe,
      responseCodec: SwitchboardOwnerContractCodecs.codecSbServed,
    );
  }

  @override
  Future<SbServed> serve(SbServe request, {RpcContext? context}) {
    return callUnary<SbServe, SbServed>(
      methodName: SwitchboardOwnerContractNames.serve,
      requestCodec: SwitchboardOwnerContractCodecs.codecSbServe,
      responseCodec: SwitchboardOwnerContractCodecs.codecSbServed,
      request: request,
      context: context,
    );
  }

  Future<SbServed> onServe(SbServe request, {RpcContext? context});
}

class SwitchboardOwnerContractPeerCaller extends RpcPeerContract
    implements ISwitchboardOwnerContract {
  SwitchboardOwnerContractPeerCaller(
    RpcPeerEndpoint endpoint, {
    String? serviceNameOverride,
    RpcDataTransferMode dataTransferMode = RpcDataTransferMode.auto,
  }) : super(
         serviceNameOverride ?? SwitchboardOwnerContractNames.service,
         endpoint,
         dataTransferMode: dataTransferMode,
         callerDataTransferMode: dataTransferMode,
       );

  @override
  void setup() {}

  @override
  Future<SbServed> serve(SbServe request, {RpcContext? context}) {
    return callUnary<SbServe, SbServed>(
      methodName: SwitchboardOwnerContractNames.serve,
      requestCodec: SwitchboardOwnerContractCodecs.codecSbServe,
      responseCodec: SwitchboardOwnerContractCodecs.codecSbServed,
      request: request,
      context: context,
    );
  }
}
