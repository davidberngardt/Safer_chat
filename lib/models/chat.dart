// chat.dart

class Chat {
  final int id;
  final String title;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;
  final List<int> participants;
  final bool isAIChat;
  final bool isMuted;
  final bool isPinned;
  final bool isArchived;
  final DateTime? archivedAt;
  final int myUserId;
  final bool isBlocked;
  final bool isChannel;
  final int? recipientUserId;
  final bool isGroup; // ✅ ДОБАВЛЕНО: флаг группы

  const Chat({
    required this.id,
    required this.title,
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
    this.participants = const [],
    this.isAIChat = false,
    this.isMuted = false,
    this.isPinned = false,
    this.isArchived = false,
    this.archivedAt,
    required this.myUserId,
    this.isBlocked = false,
    this.isChannel = false,
    this.recipientUserId,
    this.isGroup = false, // ✅ ДОБАВЛЕНО: по умолчанию false
  });

  // ✅ Фабричный метод для создания AI чата
  factory Chat.aiChat({
    required int id,
    required int myUserId,
    String title = '🤖 AI Ассистент',
    String? lastMessage,
    DateTime? lastMessageTime,
    int unreadCount = 0,
    bool isArchived = false,
    DateTime? archivedAt,
    bool isBlocked = false,
  }) {
    return Chat(
      id: id,
      title: title,
      lastMessage: lastMessage ?? 'Чем могу помочь?',
      lastMessageTime: lastMessageTime ?? DateTime.now(),
      unreadCount: unreadCount,
      participants: [myUserId, -1],
      isAIChat: true,
      isMuted: false,
      isPinned: false,
      isArchived: isArchived,
      archivedAt: archivedAt,
      myUserId: myUserId,
      isBlocked: false,
      isChannel: false,
      isGroup: false, // ✅ ДОБАВЛЕНО: AI чат не группа
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
    bool isMuted = false,
    bool isPinned = false,
    bool isArchived = false,
    DateTime? archivedAt,
    required int myUserId,
    bool isBlocked = false,
    bool isChannel = false,
    int? recipientUserId,
    bool isGroup = false, // ✅ ДОБАВЛЕНО: параметр группы
  }) {
    return Chat(
      id: id,
      title: title,
      lastMessage: lastMessage,
      lastMessageTime: lastMessageTime,
      unreadCount: unreadCount,
      participants: participants,
      isAIChat: false,
      isMuted: isMuted,
      isPinned: isPinned,
      isArchived: isArchived,
      archivedAt: archivedAt,
      myUserId: myUserId,
      isBlocked: isBlocked,
      isChannel: isChannel,
      recipientUserId: recipientUserId,
      isGroup: isGroup, // ✅ ДОБАВЛЕНО
    );
  }

  // ✅ Фабричный метод для создания архивированного чата
  factory Chat.archived({
    required int id,
    required String title,
    String? lastMessage,
    DateTime? lastMessageTime,
    int unreadCount = 0,
    required List<int> participants,
    bool isMuted = false,
    bool isPinned = false,
    required int myUserId,
    DateTime? archivedAt,
    bool isBlocked = false,
    bool isChannel = false,
    int? recipientUserId,
    bool isGroup = false, // ✅ ДОБАВЛЕНО
  }) {
    return Chat(
      id: id,
      title: title,
      lastMessage: lastMessage,
      lastMessageTime: lastMessageTime,
      unreadCount: unreadCount,
      participants: participants,
      isAIChat: false,
      isMuted: isMuted,
      isPinned: isPinned,
      isArchived: true,
      archivedAt: archivedAt ?? DateTime.now(),
      myUserId: myUserId,
      isBlocked: isBlocked,
      isChannel: isChannel,
      recipientUserId: recipientUserId,
      isGroup: isGroup, // ✅ ДОБАВЛЕНО
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
    bool? isMuted,
    bool? isPinned,
    bool? isArchived,
    DateTime? archivedAt,
    int? myUserId,
    bool? isBlocked,
    bool? isChannel,
    int? recipientUserId,
    bool? isGroup, // ✅ ДОБАВЛЕНО
  }) {
    return Chat(
      id: id ?? this.id,
      title: title ?? this.title,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      participants: participants ?? this.participants,
      isAIChat: isAIChat ?? this.isAIChat,
      isMuted: isMuted ?? this.isMuted,
      isPinned: isPinned ?? this.isPinned,
      isArchived: isArchived ?? this.isArchived,
      archivedAt: archivedAt ?? this.archivedAt,
      myUserId: myUserId ?? this.myUserId,
      isBlocked: isBlocked ?? this.isBlocked,
      isChannel: isChannel ?? this.isChannel,
      recipientUserId: recipientUserId ?? this.recipientUserId,
      isGroup: isGroup ?? this.isGroup, // ✅ ДОБАВЛЕНО
    );
  }

  // ✅ Метод для архивации чата
  Chat archive() {
    return copyWith(
      isArchived: true,
      archivedAt: DateTime.now(),
    );
  }

  // ✅ Метод для восстановления чата из архива
  Chat restore() {
    return copyWith(
      isArchived: false,
      archivedAt: null,
    );
  }

  // ✅ Метод для переключения звука
  Chat toggleMute() {
    return copyWith(
      isMuted: !isMuted,
    );
  }

  // ✅ Метод для переключения закрепления
  Chat togglePin() {
    return copyWith(
      isPinned: !isPinned,
    );
  }

  // ✅ Метод для блокировки/разблокировки чата
  Chat toggleBlock() {
    return copyWith(
      isBlocked: !isBlocked,
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
      'isAIChat': isAIChat,
      'isMuted': isMuted,
      'isPinned': isPinned,
      'isArchived': isArchived,
      'archivedAt': archivedAt?.toIso8601String(),
      'myUserId': myUserId,
      'isBlocked': isBlocked,
      'isChannel': isChannel,
      'recipientUserId': recipientUserId,
      'isGroup': isGroup, // ✅ ДОБАВЛЕНО
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
      isAIChat: map['isAIChat'] ?? false,
      isMuted: map['isMuted'] ?? false,
      isPinned: map['isPinned'] ?? false,
      isArchived: map['isArchived'] ?? false,
      archivedAt: map['archivedAt'] != null
          ? DateTime.parse(map['archivedAt'])
          : null,
      myUserId: map['myUserId'] ?? 1,
      isBlocked: map['isBlocked'] ?? false,
      isChannel: map['isChannel'] ?? false,
      recipientUserId: map['participantid'] ?? map['participantId'] ?? map['recipientUserId'],
      isGroup: map['isGroup'] ?? false, // ✅ ДОБАВЛЕНО
    );
  }

  // ✅ Вспомогательные геттеры
  bool get hasUnreadMessages => unreadCount > 0;
  bool get hasParticipants => participants.isNotEmpty;
  int get participantCount => participants.length;
  bool get canBeArchived => !isAIChat && !isChannel && !isGroup; // ✅ Группы тоже нельзя архивировать
  bool get canBeBlocked => !isAIChat && !isChannel && !isGroup; // ✅ Группы нельзя блокировать

  // ✅ Проверка, является ли пользователь участником чата
  bool isParticipant(int userId) => participants.contains(userId);

  // ✅ Получение времени архивации в формате строки
  String? get archivedAtFormatted {
    if (archivedAt == null) return null;
    final now = DateTime.now();
    final difference = now.difference(archivedAt!);

    if (difference.inDays == 0) {
      return 'Сегодня';
    } else if (difference.inDays == 1) {
      return 'Вчера';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} дн. назад';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '$weeks нед. назад';
    } else {
      final months = (difference.inDays / 30).floor();
      return '$months мес. назад';
    }
  }

  @override
  String toString() {
    return 'Chat(id: $id, title: $title, lastMessage: $lastMessage, '
        'unreadCount: $unreadCount, participants: $participants, '
        'isAIChat: $isAIChat, isMuted: $isMuted, isPinned: $isPinned, '
        'isArchived: $isArchived, isBlocked: $isBlocked, isChannel: $isChannel, '
        'isGroup: $isGroup, archivedAt: $archivedAt, myUserId: $myUserId)';
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
        other.isAIChat == isAIChat &&
        other.isMuted == isMuted &&
        other.isPinned == isPinned &&
        other.isArchived == isArchived &&
        other.isBlocked == isBlocked &&
        other.isChannel == isChannel &&
        other.isGroup == isGroup &&
        other.archivedAt == archivedAt &&
        other.myUserId == myUserId;
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
      isAIChat,
      isMuted,
      isPinned,
      isArchived,
      isBlocked,
      isChannel,
      isGroup,
      archivedAt,
      myUserId,
    );
  }
}