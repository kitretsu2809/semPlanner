import 'package:objectbox/objectbox.dart';

@Entity()
class ChatMessage {
  @Id()
  int id = 0;

  String courseId; // links to Course
  String text;
  bool isAi;
  DateTime timestamp;

  ChatMessage({
    this.id = 0,
    required this.courseId,
    required this.text,
    required this.isAi,
    required this.timestamp,
  });
}
