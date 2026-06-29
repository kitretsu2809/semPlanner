import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:semplanner/core/theme.dart';
import 'package:semplanner/core/providers/app_providers.dart';
import 'package:semplanner/core/models/chat_message.dart';
import 'package:semplanner/core/models/document_chunk.dart';
import 'package:semplanner/core/models/course.dart';

class ChatRoadmapScreen extends ConsumerStatefulWidget {
  final String courseId;
  const ChatRoadmapScreen({super.key, required this.courseId});

  @override
  ConsumerState<ChatRoadmapScreen> createState() => _ChatRoadmapScreenState();
}

class _ChatRoadmapScreenState extends ConsumerState<ChatRoadmapScreen> {
  final TextEditingController _msgController = TextEditingController();
  List<ChatMessage> _messages = [];
  bool _isTyping = false;
  
  @override
  void initState() {
    super.initState();
    _loadMessages();
  }
  
  @override
  void dispose() {
    _triggerProgressAgent();
    _msgController.dispose();
    super.dispose();
  }
  
  Future<void> _triggerProgressAgent() async {
    final aiService = ref.read(aiServiceProvider);
    final db = ref.read(objectBoxProvider);
    if (aiService != null) {
      // Run asynchronously without awaiting, allowing UI to dispose immediately
      aiService.updateLearningProgress(widget.courseId, db);
    }
  }
  
  void _loadMessages() {
    final db = ref.read(objectBoxProvider);
    final allMessages = db.store.box<ChatMessage>().getAll();
    setState(() {
      _messages = allMessages
          .where((m) => m.courseId == widget.courseId)
          .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    });
  }

  List<ChatMessage> _recentHistory({int maxMessages = 8}) {
    if (_messages.isEmpty) return const [];
    final recent = _messages.skip(1).take(maxMessages).toList();
    return recent.reversed.toList();
  }

  Future<void> _sendMessage() async {
    if (_msgController.text.trim().isEmpty) return;
    
    final prompt = _msgController.text.trim();
    _msgController.clear();
    
    final db = ref.read(objectBoxProvider);
    final aiService = ref.read(aiServiceProvider);
    
    final userMsg = ChatMessage(text: prompt, isAi: false, courseId: widget.courseId, timestamp: DateTime.now());
    db.store.box<ChatMessage>().put(userMsg);
    
    setState(() {
      _messages.insert(0, userMsg);
      _isTyping = true;
    });

    if (aiService == null) {
      setState(() => _isTyping = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('AI Service not initialized.')));
      return;
    }

    try {
      final allChunks = db.chunkBox.getAll().where((c) => c.courseId == widget.courseId).toList();
      
      // Semantic Vector Search for Chat Query
      final queryEmbedding = await aiService.generateEmbedding(prompt);
      
      allChunks.sort((a, b) {
        double simA = 0;
        double simB = 0;
        if (queryEmbedding.isNotEmpty && (a.embedding?.isNotEmpty ?? false) && (b.embedding?.isNotEmpty ?? false)) {
          simA = aiService.calculateCosineSimilarity(queryEmbedding, a.embedding ?? []);
          simB = aiService.calculateCosineSimilarity(queryEmbedding, b.embedding ?? []);
        } else {
          simA = aiService.calculateKeywordSimilarity(prompt, a.text);
          simB = aiService.calculateKeywordSimilarity(prompt, b.text);
        }
        return simB.compareTo(simA); // Descending order
      });
      
      // Limit to top 10 most semantically relevant chunks
      final topChunks = allChunks.take(10).toList();
      
      final courseList = db.store.box<Course>().getAll().where((c) => c.courseId == widget.courseId).toList();
      final progressSummary = courseList.isNotEmpty ? courseList.first.progressSummary : '';
      
      String globalObjective = '';
      if (widget.courseId == 'general_tutor') {
        globalObjective = await aiService.getGlobalObjective();
      }
      
      final responseText = await aiService.chatWithContext(
        prompt,
        topChunks,
        history: _recentHistory(),
        progressSummary: progressSummary,
        globalObjective: globalObjective,
      );
      
      final aiMsg = ChatMessage(text: responseText, isAi: true, courseId: widget.courseId, timestamp: DateTime.now());
      db.store.box<ChatMessage>().put(aiMsg);
      
      setState(() {
        _messages.insert(0, aiMsg);
        _isTyping = false;
      });
    } catch(e) {
      setState(() => _isTyping = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _generateRoadmap() async {
    final aiService = ref.read(aiServiceProvider);
    final db = ref.read(objectBoxProvider);
    
    if (aiService == null) return;
    
    setState(() => _isTyping = true);

    try {
      final allChunks = db.chunkBox.getAll().where((c) => c.courseId == widget.courseId).toList();
      
      if (allChunks.isEmpty) {
        setState(() => _isTyping = false);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No text found for this course.')));
        return;
      }
      
      final courseList = db.store.box<Course>().getAll();
      Course? course;
      for (var c in courseList) {
        if (c.courseId == widget.courseId) course = c;
      }
      final courseName = course?.name ?? 'Unknown Course';

      // Semantic Vector Search to isolate syllabus text for THIS specific course
      final queryText = 'Course syllabus, topics, and structure for $courseName';
      final queryEmbedding = await aiService.generateEmbedding(queryText);
      
      allChunks.sort((a, b) {
        double simA = 0;
        double simB = 0;
        if (queryEmbedding.isNotEmpty && (a.embedding?.isNotEmpty ?? false) && (b.embedding?.isNotEmpty ?? false)) {
          simA = aiService.calculateCosineSimilarity(queryEmbedding, a.embedding ?? []);
          simB = aiService.calculateCosineSimilarity(queryEmbedding, b.embedding ?? []);
        } else {
          simA = aiService.calculateKeywordSimilarity(queryText, a.text);
          simB = aiService.calculateKeywordSimilarity(queryText, b.text);
        }
        return simB.compareTo(simA); // Descending order
      });
      
      // Grab top 20 most relevant chunks to build the roadmap
      final topChunks = allChunks.take(20).toList();

      String globalObjective = '';
      if (widget.courseId == 'general_tutor') {
        globalObjective = await aiService.getGlobalObjective();
      }

      final roadmapText = await aiService.generateAgenticRoadmap(
        courseName, 
        topChunks,
        globalObjective: globalObjective,
      );
      
      final aiMsg = ChatMessage(text: roadmapText, isAi: true, courseId: widget.courseId, timestamp: DateTime.now());
      db.store.box<ChatMessage>().put(aiMsg);
      
      setState(() {
        _messages.insert(0, aiMsg);
        _isTyping = false;
      });
      
    } catch (e) {
      setState(() => _isTyping = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('AI Study Buddy'),
        actions: [
          IconButton(
            icon: const Icon(Icons.map, color: AppTheme.primaryBlue),
            tooltip: 'Generate Roadmap',
            onPressed: _isTyping ? null : _generateRoadmap,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: _buildChat(),
      ),
    );
  }

  Widget _buildChat() {
    return Column(
      children: [
        Expanded(
          child: _messages.isEmpty 
          ? const Center(child: Text('Ask me anything about this document!', style: TextStyle(color: AppTheme.textLight)))
          : ListView.builder(
            reverse: true, // index 0 is at the bottom
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length + (_isTyping ? 1 : 0),
            itemBuilder: (context, index) {
              if (_isTyping && index == 0) {
                return const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: SizedBox(
                      width: 24, height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              final msgIndex = _isTyping ? index - 1 : index;
              final msg = _messages[msgIndex];
              return _buildChatBubble(text: msg.text, isAi: msg.isAi);
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _msgController,
                  decoration: InputDecoration(
                    hintText: 'Ask your syllabus a question...',
                    filled: true,
                    fillColor: AppTheme.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: const BoxDecoration(
                  color: AppTheme.primaryBlue,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white, size: 20),
                  onPressed: _sendMessage,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChatBubble({required String text, required bool isAi}) {
    return Align(
      alignment: isAi ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.80),
        decoration: BoxDecoration(
          color: isAi ? Colors.white : AppTheme.primaryBlue,
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomLeft: isAi ? const Radius.circular(0) : const Radius.circular(16),
            bottomRight: !isAi ? const Radius.circular(0) : const Radius.circular(16),
          ),
          border: isAi ? Border.all(color: Colors.grey.shade200) : null,
        ),
        child: isAi 
          ? MarkdownBody(
              data: text,
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(color: AppTheme.textDark, fontSize: 15),
                h1: const TextStyle(color: AppTheme.primaryBlue, fontSize: 24, fontWeight: FontWeight.bold),
                h2: const TextStyle(color: AppTheme.primaryBlue, fontSize: 20, fontWeight: FontWeight.bold),
                h3: const TextStyle(color: AppTheme.primaryBlue, fontSize: 18, fontWeight: FontWeight.bold),
                listBullet: const TextStyle(color: AppTheme.primaryBlue, fontSize: 15),
                code: TextStyle(backgroundColor: Colors.grey.shade100, fontFamily: 'monospace', fontSize: 14),
                codeblockDecoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            )
          : Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
      ),
    );
  }
}
