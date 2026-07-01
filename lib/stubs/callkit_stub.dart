library callkit_stub;

class Event {
  static const actionCallAccept = 'actionCallAccept';
  static const actionCallDecline = 'actionCallDecline';
  static const actionCallEnded = 'actionCallEnded';
  static const actionCallMuted = 'actionCallMuted';
  static const actionCallHeld = 'actionCallHeld';
}

class FlutterCallkitIncoming {
  static final FlutterCallkitIncoming _instance = FlutterCallkitIncoming._internal();

  factory FlutterCallkitIncoming() {
    return _instance;
  }

  FlutterCallkitIncoming._internal();

  static Stream<CallEvent> get onEvent => const Stream.empty();

  Stream<String>? get onTokenRefreshed => null;

  Stream<Map<String, dynamic>>? get onDidReceiveIncomingPush => null;

  Future<void> registerVoIPPush() async {}

  static Future<void> showCallkitIncoming(CallKitParams params) async {}

  static Future<void> endCall(String id) async {}

  static Future<void> endAllCalls() async {}
}

class CallEvent {
  final String? event;
  final Map<String, dynamic>? body;

  CallEvent({this.event, this.body});
}

class CallKitParams {
  final String id;
  final String nameCaller;
  final String handle;
  final int type;
  final int duration;
  final String textDisplay;
  final Map<String, dynamic> extra;
  final IOSOptions? ios;

  CallKitParams({
    required this.id,
    required this.nameCaller,
    required this.handle,
    required this.type,
    required this.duration,
    required this.textDisplay,
    required this.extra,
    this.ios,
  });
}

class IOSOptions {
  final String iconName;
  final String handleType;
  final bool supportsVideo;
  final int maximumCallGroups;
  final int maximumCallsPerCallGroup;
  final String audioSessionMode;
  final bool audioSessionActive;
  final double audioSessionPreferredSampleRate;
  final double audioSessionPreferredIOBufferDuration;
  final bool supportsDTMF;
  final bool supportsHolding;
  final bool supportsGrouping;
  final bool supportsUngrouping;
  final String ringtonePath;

  IOSOptions({
    required this.iconName,
    required this.handleType,
    required this.supportsVideo,
    required this.maximumCallGroups,
    required this.maximumCallsPerCallGroup,
    required this.audioSessionMode,
    required this.audioSessionActive,
    required this.audioSessionPreferredSampleRate,
    required this.audioSessionPreferredIOBufferDuration,
    required this.supportsDTMF,
    required this.supportsHolding,
    required this.supportsGrouping,
    required this.supportsUngrouping,
    required this.ringtonePath,
  });
}