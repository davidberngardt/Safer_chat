class Chat {
  final int id;
  final String title;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;
  final List<int> participants;
  final bool isAIChat; // ✅ Новое поле для AI чатов

  const Chat({
    required this.id,
    required this.title,
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
    this.participants = const [],
    this.isAIChat = false, // ✅ По умолчанию false
  });

  // ✅ Фабричный метод для создания AI чата
  factory Chat.aiChat({
    required int id,
    String title = '🤖 AI Ассистент',
    String? lastMessage,
    DateTime? lastMessageTime,
    int unreadCount = 0,
    int myUserId = 1,
  }) {
    return Chat(
      id: id,
      title: title,
      lastMessage: lastMessage ?? 'Чем могу помочь?',
      lastMessageTime: lastMessageTime ?? DateTime.now(),
      unreadCount: unreadCount,
      participants: [myUserId, -1], // ✅ -1 для AI участника
      isAIChat: true, // ✅ Помечаем как AI чат
    );
  }

  // ✅ Фабричный метод для создания обычного чата
  factory Chat.regular({
    required int id,
    required String title,
    String? lastMessage,
    DateTime? lastMessageTime,
    int unreadCount = 0,
    required List<int> participants,
  }) {
    return Chat(
      id: id,
      title: title,
      lastMessage: lastMessage,
      lastMessageTime: lastMessageTime,
      unreadCount: unreadCount,
      participants: participants,
      isAIChat: false, // ✅ Обычный чат
    );
  }

  // ✅ Метод для копирования с изменениями
  Chat copyWith({
    int? id,
    String? title,
    String? lastMessage,
    DateTime? lastMessageTime,
    int? unreadCount,
    List<int>? participants,
    bool? isAIChat,
  }) {
    return Chat(
      id: id ?? this.id,
      title: title ?? this.title,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      participants: participants ?? this.participants,
      isAIChat: isAIChat ?? this.isAIChat,
    );
  }

  // ✅ Конвертация в Map (для сохранения в БД)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'lastMessage': lastMessage,
      'lastMessageTime': lastMessageTime?.toIso8601String(),
      'unreadCount': unreadCount,
      'participants': participants,
      'isAIChat': isAIChat, // ✅ Сохраняем флаг AI
    };
  }

  // ✅ Создание из Map (для загрузки из БД)
  factory Chat.fromMap(Map<String, dynamic> map) {
    return Chat(
      id: map['id'],
      title: map['title'],
      lastMessage: map['lastMessage'],
      lastMessageTime: map['lastMessageTime'] != null 
          ? DateTime.parse(map['lastMessageTime']) 
          : null,
      unreadCount: map['unreadCount'] ?? 0,
      participants: List<int>.from(map['participants'] ?? []),
      isAIChat: map['isAIChat'] ?? false, // ✅ Загружаем флаг AI
    );
  }

  // ✅ Вспомогательные геттеры
  bool get hasUnreadMessages => unreadCount > 0;
  bool get hasParticipants => participants.isNotEmpty;
  int get participantCount => participants.length;
  
  // ✅ Проверка, является ли пользователь участником чата
  bool isParticipant(int userId) => participants.contains(userId);

  @override
  String toString() {
    return 'Chat(id: $id, title: $title, lastMessage: $lastMessage, '
           'unreadCount: $unreadCount, participants: $participants, '
           'isAIChat: $isAIChat)'; // ✅ Добавляем isAIChat в toString
  }

  // ✅ Для сравнения чатов
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Chat &&
        other.id == id &&
        other.title == title &&
        other.lastMessage == lastMessage &&
        other.lastMessageTime == lastMessageTime &&
        other.unreadCount == unreadCount &&
        other.participants.length == participants.length &&
        other.isAIChat == isAIChat; // ✅ Сравниваем флаг AI
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      title,
      lastMessage,
      lastMessageTime,
      unreadCount,
      participants.length,
      isAIChat, // ✅ Включаем в хэш-код
    );
  }
}