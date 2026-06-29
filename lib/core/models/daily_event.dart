import 'package:objectbox/objectbox.dart';

@Entity()
class DailyEvent {
  @Id()
  int id;

  String dayOfWeek; // e.g., "Monday"
  String startTime; // e.g., "09:00 AM"
  String endTime;   // e.g., "10:30 AM"
  String title;     // e.g., "Advanced Algorithms"
  String subtitle;  // e.g., "Lecture Hall B • Prof. Richardson"
  String category;  // e.g., "lecture", "mess", "lab"

  DailyEvent({
    this.id = 0,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.title,
    required this.subtitle,
    required this.category,
  });
}
