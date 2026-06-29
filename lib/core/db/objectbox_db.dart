import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:semplanner/objectbox.g.dart';
import 'package:semplanner/core/models/document_chunk.dart';

class ObjectBoxDB {
  /// The Store of this app.
  late final Store store;
  
  late final Box<DocumentChunk> chunkBox;

  ObjectBoxDB._create(this.store) {
    chunkBox = Box<DocumentChunk>(store);
  }

  /// Create an instance of ObjectBox to use throughout the app.
  static Future<ObjectBoxDB> create() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final store = await openStore(directory: p.join(docsDir.path, "semplanner-db"));
    return ObjectBoxDB._create(store);
  }

  /// Vector Search Function:
  /// Given an embedding vector, find the top `k` closest DocumentChunks.
  List<DocumentChunk> searchSimilarChunks(List<double> queryEmbedding, {int maxResults = 5}) {
    final query = chunkBox.query(
      DocumentChunk_.embedding.nearestNeighborsF32(queryEmbedding, maxResults)
    ).build();
    
    final results = query.find();
    query.close();
    
    return results;
  }
}
