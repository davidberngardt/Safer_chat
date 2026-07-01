import '../utils/platform_utils.dart';

class CallHistory {
  final int id;
  final int chatId;
  final int callerId;
  final int recipientId;
  final DateTime startTime;
  final DateTime? endTime;
  final int? duration;
  final String status; // 'completed', 'missed', 'cancelled'
  final String? callType; // 'audio', 'video'

  CallHistory({
    required this.id,
    required this.chatId,
    required this.callerId,
    required this.recipientId,
    required this.startTime,
    this.endTime,
    this.duration,
    required this.status,
    this.callType,
  });

  factory CallHistory.fromMap(Map<String, dynamic> map) {
    return CallHistory(
      id: map['id'],
      chatId: map['chat_id'],
      callerId: map['caller_id'],
      recipientId: map['recipient_id'],
      startTime: DateTime.parse(map['start_time']),
      endTime: map['end_time'] != null ? DateTime.parse(map['end_time']) : null,
      duration: map['duration'],
      status: map['status'],
      callType: map['call_type'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'chat_id': chatId,
      'caller_id': callerId,
      'recipient_id': recipientId,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'duration': duration,
      'status': status,
      'call_type': callType,
    };
  }
}