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
}

class SwitchboardContractCodecs {
  const SwitchboardContractCodecs._();
  static const codecRpcNull = RpcCodec<RpcNull>(RpcNull.fromJson);
  static const codecSbCallReply = RpcCodec<SbCallReply>(SbCallReply.fromJson);
  static const codecSbCallRequest = RpcCodec<SbCallRequest>(
    SbCallRequest.fromJson,
  );
  static const codecSbDescription = RpcCodec<SbDescription>(
    SbDescription.fromJson,
  );
  static const codecSbFeedItem = RpcCodec<SbFeedItem>(SbFeedItem.fromJson);
  static const codecSbFeedRequest = RpcCodec<SbFeedRequest>(
    SbFeedRequest.fromJson,
  );
  static const codecSbLayerEvent = RpcCodec<SbLayerEvent>(
    SbLayerEvent.fromJson,
  );
  static const codecSbLayerRef = RpcCodec<SbLayerRef>(SbLayerRef.fromJson);
  static const codecSbLayerRequest = RpcCodec<SbLayerRequest>(
    SbLayerRequest.fromJson,
  );
}

class SwitchboardContractCaller extends RpcCallerContract
    implements ISwitchboardContract {
  SwitchboardContractCaller(
    RpcCallerEndpoint endpoint, {
    String? serviceNameOverride,
    RpcDataTransferMode dataTransferMode = RpcDataTransferMode.auto,
  }) : super(
         serviceNameOverride ?? SwitchboardContractNames.service,
         endpoint,
         dataTransferMode: dataTransferMode,
       );

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
}

abstract class SwitchboardContractResponder extends RpcResponderContract
    implements ISwitchboardContract {
  SwitchboardContractResponder({
    String? serviceNameOverride,
    RpcDataTransferMode dataTransferMode = RpcDataTransferMode.auto,
  }) : super(
         serviceNameOverride ?? SwitchboardContractNames.service,
         dataTransferMode: dataTransferMode,
       );

  @override
  void setup() {
    addUnaryMethod<RpcNull, SbDescription>(
      methodName: SwitchboardContractNames.describe,
      handler: describe,
      requestCodec: SwitchboardContractCodecs.codecRpcNull,
      responseCodec: SwitchboardContractCodecs.codecSbDescription,
    );
    addServerStreamMethod<SbFeedRequest, SbFeedItem>(
      methodName: SwitchboardContractNames.feed,
      handler: feed,
      requestCodec: SwitchboardContractCodecs.codecSbFeedRequest,
      responseCodec: SwitchboardContractCodecs.codecSbFeedItem,
    );
    addUnaryMethod<SbCallRequest, SbCallReply>(
      methodName: SwitchboardContractNames.invoke,
      handler: invoke,
      requestCodec: SwitchboardContractCodecs.codecSbCallRequest,
      responseCodec: SwitchboardContractCodecs.codecSbCallReply,
    );
    addUnaryMethod<SbLayerRequest, SbLayerRef>(
      methodName: SwitchboardContractNames.pushLayer,
      handler: pushLayer,
      requestCodec: SwitchboardContractCodecs.codecSbLayerRequest,
      responseCodec: SwitchboardContractCodecs.codecSbLayerRef,
    );
    addUnaryMethod<SbLayerRef, RpcNull>(
      methodName: SwitchboardContractNames.popLayer,
      handler: popLayer,
      requestCodec: SwitchboardContractCodecs.codecSbLayerRef,
      responseCodec: SwitchboardContractCodecs.codecRpcNull,
    );
    addServerStreamMethod<RpcNull, SbLayerEvent>(
      methodName: SwitchboardContractNames.layerEvents,
      handler: layerEvents,
      requestCodec: SwitchboardContractCodecs.codecRpcNull,
      responseCodec: SwitchboardContractCodecs.codecSbLayerEvent,
    );
  }
}
