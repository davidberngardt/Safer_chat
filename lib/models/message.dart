import '../utils/platform_utils.dart';

class Message {
  final int id;
  final int userId;
  final String text;
  final DateTime createdAt;
  final String? fileUrl;
  final int typeId;
  final int? duration;
  final bool isForwarded;
  final String? forwardedFrom;
  final bool isPinned;
  final DateTime? updatedAt;
  
  Message({
    required this.id,
    required this.userId,
    required this.text,
    required this.createdAt,
    this.fileUrl,
    required this.typeId,
    this.duration,
    this.isForwarded = false,
    this.forwardedFrom,
    this.isPinned = false,
    this.updatedAt,
  });

  // Getters для типов сообщений
  bool get isImage => typeId == 2 && _isImageFile(fileUrl ?? '');
  bool get isVideo => typeId == 2 && _isVideoFile(fileUrl ?? '');
  bool get isFile => typeId == 2 && !isImage && !isVideo;
  bool get isVoice => typeId == 4;
  bool get isText => typeId == 1;
  bool get isAudioFile => typeId == 4 || _isAudioFile(fileUrl ?? '');

  String? get fileName {
    if (fileUrl == null) return null;
    final uri = Uri.parse(fileUrl!);
    return uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'file';
  }

  bool _isImageFile(String url) {
    final imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'];
    final ext = url.toLowerCase().split('.').last;
    return imageExtensions.contains(ext);
  }

  bool _isVideoFile(String url) {
    final videoExtensions = ['mp4', 'avi', 'mov', 'wmv', 'flv', 'webm'];
    final ext = url.toLowerCase().split('.').last;
    return videoExtensions.contains(ext);
  }

  bool _isAudioFile(String url) {
    final audioExtensions = ['mp3', 'wav', 'm4a', 'aac', 'ogg'];
    final ext = url.toLowerCase().split('.').last;
    return audioExtensions.contains(ext);
  }

  // AI чат методы
  bool get isFromAI => userId == -1;
  bool get isFromUser => !isFromAI;

  factory Message.fromAI({
    required int id,
    required String text,
    DateTime? createdAt,
    bool isForwarded = false,
    String? forwardedFrom,
  }) {
    return Message(
      id: id,
      userId: -1,
      text: text,
      createdAt: createdAt ?? DateTime.now(),
      typeId: 1,
      fileUrl: null,
      duration: null,
      isForwarded: isForwarded,
      forwardedFrom: forwardedFrom,
    );
  }

  factory Message.fromUser({
    required int id,
    required int userId,
    required String text,
    DateTime? createdAt,
    String? fileUrl,
    int typeId = 1,
    int? duration,
    bool isForwarded = false,
    String? forwardedFrom,
  }) {
    return Message(
      id: id,
      userId: userId,
      text: text,
      createdAt: createdAt ?? DateTime.now(),
      fileUrl: fileUrl,
      typeId: typeId,
      duration: duration,
      isForwarded: isForwarded,
      forwardedFrom: forwardedFrom,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'text': text,
      'createdAt': createdAt.toIso8601String(),
      'fileUrl': fileUrl,
      'typeId': typeId,
      'duration': duration,
      'isForwarded': isForwarded,
      'forwardedFrom': forwardedFrom,
      'isPinned': isPinned,
    };
  }

  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id'],
      userId: map['user_id'] ?? map['userId'],
      text: map['text'] ?? '',
      createdAt: map['created_at'] != null 
          ? DateTime.parse(map['created_at']).toLocal()
          : DateTime.now(),
      fileUrl: map['file_url'] ?? map['fileUrl'],
      typeId: map['type_id'] ?? map['typeId'] ?? 1,
      duration: map['duration'],
      isForwarded: map['is_forwarded'] ?? map['isForwarded'] ?? false,
      forwardedFrom: map['forwarded_from'] ?? map['forwardedFrom'],
      isPinned: map['is_pinned'] ?? map['isPinned'] ?? false,
      updatedAt: map['updated_at'] != null 
          ? DateTime.parse(map['updated_at']).toLocal()
          : null,
    );
  }

  Message copyWith({
    int? id,
    int? userId,
    String? text,
    DateTime? createdAt,
    String? fileUrl,
    int? typeId,
    int? duration,
    bool? isForwarded,
    String? forwardedFrom,
    bool? isPinned,
    DateTime? updatedAt,
  }) {
    return Message(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      fileUrl: fileUrl ?? this.fileUrl,
      typeId: typeId ?? this.typeId,
      duration: duration ?? this.duration,
      isForwarded: isForwarded ?? this.isForwarded,
      forwardedFrom: forwardedFrom ?? this.forwardedFrom,
      isPinned: isPinned ?? this.isPinned,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
