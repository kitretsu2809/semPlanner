import 'package:objectbox/objectbox.dart';

@Entity()
class Course {
  @Id()
  int id = 0;

  @Unique()
  String courseId; // e.g., "phys101"

  String name;
  String instructor;
  String scheduleInfo;
  String progressSummary;
  double progressPercentage;

  Course({
    this.id = 0,
    required this.courseId,
    required this.name,
    this.instructor = '',
    this.scheduleInfo = '',
    this.progressSummary = '',
    this.progressPercentage = 0.0,
  });
}
