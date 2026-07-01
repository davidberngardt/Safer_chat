class Message {
  final int id;
  final int userId;
  final String text;
  final DateTime createdAt;
  final String? fileUrl;
  final int typeId;
  final int? duration;

  Message({
    required this.id,
    required this.userId,
    required this.text,
    required this.createdAt,
    this.fileUrl,
    required this.typeId,
    this.duration,
  });

  // ✅ Существующие методы остаются без изменений
  bool get isImage => typeId == 2 && _isImageFile(fileUrl ?? '');
  bool get isVideo => typeId == 2 && _isVideoFile(fileUrl ?? '');
  bool get isFile => typeId == 2 && !isImage && !isVideo;
  bool get isVoice => typeId == 4; // ✅ Обновлено с 3 на 4 (audio type)
  bool get isText => typeId == 1;

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

  // Добавляем метод для проверки аудио файлов
  bool get isAudioFile => typeId == 4 || _isAudioFile(fileUrl ?? ''); // ✅ Обновлено с 3 на 4
  
  bool _isAudioFile(String url) {
    final audioExtensions = ['mp3', 'wav', 'm4a', 'aac', 'ogg'];
    final ext = url.toLowerCase().split('.').last;
    return audioExtensions.contains(ext);
  }

  // ✅ НОВЫЕ МЕТОДЫ ДЛЯ AI ЧАТА
  
  // Определяем, является ли сообщение от AI бота
  bool get isFromAI => userId == -1; // Используем -1 как ID для AI
  
  // Определяем, является ли сообщение от пользователя
  bool get isFromUser => !isFromAI;
  
  // Создаем фабричный метод для создания AI сообщения
  factory Message.fromAI({
    required String text,
    int id = -1, // ID для AI сообщений
    DateTime? createdAt,
  }) {
    return Message(
      id: id,
      userId: -1, // Специальный ID для AI
      text: text,
      createdAt: createdAt ?? DateTime.now(),
      typeId: 1, // Текстовый тип
      fileUrl: null,
      duration: null,
    );
  }
  
  // Создаем фабричный метод для создания пользовательского сообщения
  factory Message.fromUser({
    required int id,
    required int userId,
    required String text,
    DateTime? createdAt,
    String? fileUrl,
    int typeId = 1,
    int? duration,
  }) {
    return Message(
      id: id,
      userId: userId,
      text: text,
      createdAt: createdAt ?? DateTime.now(),
      fileUrl: fileUrl,
      typeId: typeId,
      duration: duration,
    );
  }
  
  // Конвертируем в Map (полезно для сохранения в БД)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'text': text,
      'createdAt': createdAt.toIso8601String(),
      'fileUrl': fileUrl,
      'typeId': typeId,
      'duration': duration,
    };
  }
  
  // Создаем из Map (полезно для загрузки из БД)
  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id'],
      userId: map['userId'],
      text: map['text'],
      createdAt: DateTime.parse(map['createdAt']),
      fileUrl: map['fileUrl'],
      typeId: map['typeId'],
      duration: map['duration'],
    );
  }
  
  // Копируем сообщение с изменениями (полезно для обновлений)
  Message copyWith({
    int? id,
    int? userId,
    String? text,
    DateTime? createdAt,
    String? fileUrl,
    int? typeId,
    int? duration,
  }) {
    return Message(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      fileUrl: fileUrl ?? this.fileUrl,
      typeId: typeId ?? this.typeId,
      duration: duration ?? this.duration,
    );
  }
}