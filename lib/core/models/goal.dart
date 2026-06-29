import 'package:objectbox/objectbox.dart';

@Entity()
class Goal {
  @Id()
  int id;

  String title;
  double progress; // 0.0 to 1.0
  String statusText; // e.g., "You're only 4 modules away from completion!"

  Goal({
    this.id = 0,
    required this.title,
    required this.progress,
    required this.statusText,
  });
}
