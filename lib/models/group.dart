class Group {
  final int id;
  final String name;
  final String? description;
  final String? avatarUrl;
  final String avatarColor;
  final int createdBy;
  final DateTime createdAt;
  final int membersCount;
  final bool isMember;
  final List<int> memberIds;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;

  Group({
    required this.id,
    required this.name,
    this.description,
    this.avatarUrl,
    required this.avatarColor,
    required this.createdBy,
    required this.createdAt,
    required this.membersCount,
    required this.isMember,
    required this.memberIds,
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
  });

  factory Group.fromMap(Map<String, dynamic> map) {
    return Group(
      id: map['id'],
      name: map['name'] ?? '',
      description: map['description'],
      avatarUrl: map['avatar_url'],
      avatarColor: map['avatar_color'] ?? '#FF9800',
      createdBy: map['created_by'],
      createdAt: DateTime.parse(map['created_at']),
      membersCount: map['members_count'] ?? 0,
      isMember: map['is_member'] ?? false,
      memberIds: List<int>.from(map['member_ids'] ?? []),
      lastMessage: map['last_message'],
      lastMessageTime: map['last_message_time'] != null
          ? DateTime.parse(map['last_message_time'])
          : null,
      unreadCount: map['unread_count'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'avatar_url': avatarUrl,
      'avatar_color': avatarColor,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'members_count': membersCount,
      'is_member': isMember,
      'member_ids': memberIds,
      'last_message': lastMessage,
      'last_message_time': lastMessageTime?.toIso8601String(),
      'unread_count': unreadCount,
    };
  }

  bool get isOwner => createdBy == memberIds.firstWhere((id) => true, orElse: () => -1);
}