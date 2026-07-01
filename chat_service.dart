import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:encrypt/encrypt.dart';

class ChatService {
  final CollectionReference messages =
      FirebaseFirestore.instance.collection('messages');

  final Key key = Key.fromUtf8('твой_32_символьный_ключ_AES'); // AES-256
  final IV iv = IV.fromLength(16);

  // Шифруем текст
  String encryptText(String text) {
    final encrypter = Encrypter(AES(key));
    final encrypted = encrypter.encrypt(text, iv: iv);
    return encrypted.base64;
  }

  // Расшифровываем текст
  String decryptText(String encryptedText) {
    final encrypter = Encrypter(AES(key));
    final encrypted = Encrypted.fromBase64(encryptedText);
    return encrypter.decrypt(encrypted, iv: iv);
  }

  // Отправляем сообщение
  Future<void> sendMessage(String text) async {
    final encrypted = encryptText(text);
    await messages.add({
      'text': encrypted,
      'timestamp': FieldValue.serverTimestamp(),
      'userId': FirebaseAuth.instance.currentUser?.uid,
    });
  }

  // Получаем сообщения с расшифровкой и проверкой времени
  Stream<List<Map<String, dynamic>>> getMessages() {
    return messages.orderBy('timestamp', descending: false).snapshots().map(
      (snapshot) {
        return snapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          // Декодируем текст
          final text = data['text'] != null ? decryptText(data['text']) : '';
          // Получаем временную метку
          final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
          return {
            'id': doc.id,
            'userId': data['userId'],
            'text': text,
            'timestamp': timestamp,
          };
        }).toList();
      },
    );
  }

  // Удаляем старые сообщения (старше 30 дней)
  Future<void> deleteOldMessages() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final oldMessages = await messages
        .where('timestamp', isLessThan: Timestamp.fromDate(cutoff))
        .get();

    for (var doc in oldMessages.docs) {
      await doc.reference.delete();
    }
  }
}
