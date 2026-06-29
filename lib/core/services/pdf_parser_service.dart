import 'dart:io';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class PdfParserService {
  /// Extracts all text from a given PDF file.
  Future<String> extractTextFromPdf(File file) async {
    try {
      final List<int> bytes = await file.readAsBytes();
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      final PdfTextExtractor extractor = PdfTextExtractor(document);
      final String text = extractor.extractText();
      document.dispose();
      return text;
    } catch (e) {
      print('Error parsing PDF: $e');
      return '';
    }
  }

  /// Naive text chunking for embeddings.
  /// In a production app, we would use semantic chunking (e.g., by paragraph).
  List<String> chunkText(String text, {int chunkSize = 1500, int overlap = 200}) {
    if (text.isEmpty) return [];
    
    List<String> chunks = [];
    int i = 0;
    while (i < text.length) {
      int end = (i + chunkSize < text.length) ? i + chunkSize : text.length;
      chunks.add(text.substring(i, end));
      i += (chunkSize - overlap);
    }
    return chunks;
  }
}
