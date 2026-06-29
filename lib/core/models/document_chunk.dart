import 'package:objectbox/objectbox.dart';

@Entity()
class DocumentChunk {
  @Id()
  int id = 0;

  String text;
  String sourceDocument; // e.g., "Physics 101 Syllabus"
  String courseId;

  // We use HnswIndex for fast nearest-neighbor search (Vector DB)
  // Gemini embedding models output 768 dimensions by default
  @HnswIndex(dimensions: 768)
  @Property(type: PropertyType.floatVector)
  List<double>? embedding;

  DocumentChunk({
    this.id = 0,
    required this.text,
    required this.sourceDocument,
    required this.courseId,
    this.embedding,
  });
}
