import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:semplanner/core/db/objectbox_db.dart';
import 'package:semplanner/core/services/ai_service.dart';
import 'package:semplanner/core/services/pdf_parser_service.dart';

final objectBoxProvider = Provider<ObjectBoxDB>((ref) => throw UnimplementedError());

class LlmConfig {
  final String apiKey;
  final String chatModel;
  final String embeddingModel;

  LlmConfig({
    this.apiKey = '', 
    this.chatModel = 'gemini-1.5-flash',
    this.embeddingModel = 'embedding-001'
  });
}

class LlmConfigNotifier extends Notifier<LlmConfig> {
  @override
  LlmConfig build() {
    return LlmConfig();
  }

  void updateConfig({String? apiKey, String? chatModel, String? embeddingModel}) {
    state = LlmConfig(
      apiKey: apiKey ?? state.apiKey,
      chatModel: chatModel ?? state.chatModel,
      embeddingModel: embeddingModel ?? state.embeddingModel,
    );
  }

  void clearConfig() {
    state = LlmConfig();
  }
}

final llmConfigProvider = NotifierProvider<LlmConfigNotifier, LlmConfig>(() => LlmConfigNotifier());

final pdfParserProvider = Provider<PdfParserService>((ref) => PdfParserService());

final aiServiceProvider = Provider<AiService?>((ref) {
  final config = ref.watch(llmConfigProvider);
  if (config.apiKey.isEmpty) return null;
  return AiService(
    apiKey: config.apiKey,
    chatModel: config.chatModel,
    embeddingModel: config.embeddingModel,
  );
});
