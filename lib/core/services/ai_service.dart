import 'dart:math';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:semplanner/core/models/chat_message.dart';
import 'package:semplanner/core/models/document_chunk.dart';
import 'package:semplanner/core/models/daily_event.dart';
import 'package:semplanner/core/models/course.dart';
import 'package:semplanner/core/db/objectbox_db.dart';

class AiService {
  final GenerativeModel _chatModel;
  final GenerativeModel _embeddingModel;

  AiService({
    required String apiKey, 
    String chatModel = 'gemini-1.5-flash', 
    String embeddingModel = 'text-embedding-004'
  })  : _chatModel = GenerativeModel(model: chatModel, apiKey: apiKey),
        _embeddingModel = GenerativeModel(model: embeddingModel, apiKey: apiKey);

  /// Generates a 768-dimensional vector embedding for a piece of text.
  Future<List<double>> generateEmbedding(String text) async {
    try {
      final content = Content.text(text);
      final result = await _embeddingModel.embedContent(content);
      return result.embedding.values;
    } catch (e) {
      print('Embedding Failed (falling back to keyword search): $e');
      return [];
    }
  }

  /// Analyzes raw text and determines ALL appropriate course names.
  /// Uses existing course names to prevent duplicates.
  Future<List<String>> identifyCourses(String text, List<String> existingCourses) async {
    try {
      final prompt = '''
You are an intelligent data organizer for a student's study app.
Your task is to identify ALL distinct academic Course Names found in the following text (which might be a syllabus containing multiple courses).
Example formats: "Physics 101", "Data Structures (CS201)".
If it is obviously a mess menu or hostel timetable, include "Mess Menu" or "Timetable".

IMPORTANT RULES:
1. Return a COMMA-SEPARATED list of course names. (e.g. Physics 101, Intro to Chemistry, Data Structures)
2. Return ONLY the comma-separated names, no other text, no bullet points.
3. If the text belongs to one of these existing courses, return that EXACT name: [${existingCourses.join(', ')}]

Text to analyze (first 3000 chars):
${text.length > 3000 ? text.substring(0, 3000) : text}
''';
      final response = await _chatModel.generateContent([Content.text(prompt)]);
      final rawStr = response.text?.trim().replaceAll('"', '') ?? 'Unknown Course';
      final list = rawStr.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      return list.isNotEmpty ? list : ['Unknown Course'];
    } catch (e) {
      throw Exception('Course Extraction Failed: $e');
    }
  }

  /// Computes cosine similarity between two vectors
  double calculateCosineSimilarity(List<double> vecA, List<double> vecB) {
    if (vecA.length != vecB.length) return 0.0;
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    for (int i = 0; i < vecA.length; i++) {
      dotProduct += vecA[i] * vecB[i];
      normA += vecA[i] * vecA[i];
      normB += vecB[i] * vecB[i];
    }
    if (normA == 0 || normB == 0) return 0.0;
    return dotProduct / (sqrt(normA) * sqrt(normB));
  }

  /// Calculates a simple keyword intersection score if embeddings fail
  double calculateKeywordSimilarity(String query, String text) {
    final queryWords = query.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), '').split(' ').where((w) => w.isNotEmpty).toSet();
    final textWords = text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), '').split(' ').where((w) => w.isNotEmpty).toSet();
    if (queryWords.isEmpty || textWords.isEmpty) return 0.0;
    
    final intersection = queryWords.intersection(textWords).length;
    return intersection / queryWords.length.toDouble(); 
  }

  /// Calculates a similarity score between a query and a document chunk
  MapEntry<DocumentChunk, double> calculateSimilarity(
      String prompt, List<double> queryEmbedding, DocumentChunk chunk) {
    double similarity = 0;
    
    // Use vector search if embeddings exist, else fallback to keyword search
    if (queryEmbedding.isNotEmpty && (chunk.embedding?.isNotEmpty ?? false)) {
      similarity = calculateCosineSimilarity(queryEmbedding, chunk.embedding!);
    } else {
      similarity = calculateKeywordSimilarity(prompt, chunk.text);
    }
    
    return MapEntry(chunk, similarity);
  }

  /// Use Gemini Vision to extract text from an image
  Future<String> extractTextFromImage(Uint8List imageBytes, String mimeType) async {
    try {
      final prompt = Content.multi([
        TextPart('Extract all the text from this image exactly as it appears. If it is a timetable or syllabus, preserve the structure.'),
        DataPart(mimeType, imageBytes),
      ]);
      final response = await _chatModel.generateContent([prompt]);
      return response.text ?? '';
    } catch (e) {
      print('Image OCR Failed: $e');
      return '';
    }
  }

  /// Extracts structured daily schedule events from a timetable or mess menu
  Future<void> extractAndSaveSchedule(String category, String text, ObjectBoxDB db) async {
    try {
      final prompt = '''
You are an intelligent data organizer for a student's study app.
Read the following raw text from a "$category" document (which might be a class timetable or mess menu).
Extract all schedule events for the ENTIRE WEEK into a structured JSON array.
If it's a timetable, extract lectures, labs, and tutorials.
If it's a mess menu, extract breakfast, lunch, snacks, and dinner timings.

CRITICAL RULE 1 FOR dayOfWeek: You MUST use exact full day names (e.g., "Monday", "Tuesday"). Do NOT use ranges like "Mon-Fri" or "Weekdays". If an event happens on multiple days, you MUST duplicate the JSON object for each specific day it occurs.
CRITICAL RULE 2 FOR COMPLETENESS: DO NOT get lazy or stop early. You MUST exhaustively list every single event for Monday, Tuesday, Wednesday, Thursday, and Friday. Missing any day will severely impact the student's schedule.

Return ONLY a valid JSON array of objects. Do not include markdown codeblocks or any other text.
Format:
[
  {
    "dayOfWeek": "Monday",
    "startTime": "09:00 AM",
    "endTime": "10:30 AM",
    "title": "Advanced Algorithms",
    "subtitle": "Lecture Hall B",
    "category": "$category"
  }
]

Text to analyze:
${text.length > 8000 ? text.substring(0, 8000) : text}
''';
      
      final response = await _chatModel.generateContent([Content.text(prompt)]);
      final jsonStr = _extractJsonPayload(response.text) ?? '[]';
      final decoded = jsonDecode(jsonStr);
      final List<dynamic> jsonList = decoded is List ? decoded : [decoded];

      for (final item in jsonList) {
        if (item is! Map) continue;
        final map = item.cast<String, dynamic>();
        final event = DailyEvent(
          dayOfWeek: map['dayOfWeek'] ?? 'Monday',
          startTime: map['startTime'] ?? '09:00 AM',
          endTime: map['endTime'] ?? '10:00 AM',
          title: map['title'] ?? 'Unknown Event',
          subtitle: map['subtitle'] ?? '',
          category: map['category'] ?? category,
        );
        db.store.box<DailyEvent>().put(event);
      }
    } catch (e) {
      // Fail silently so it doesn't break the whole file intake process
      print('Schedule Extraction Failed: $e');
    }
  }

  /// Parses a natural language task into DailyEvents using the LLM and existing schedule context
  Future<List<DailyEvent>> parseCustomTask(String promptText, List<DailyEvent> existingEvents) async {
    try {
      // Sort existing events just in case
      final sortedEvents = List<DailyEvent>.from(existingEvents);
      // Basic string sort is ok here for context, since we just need to show gaps to LLM
      
      final scheduleStr = sortedEvents.isEmpty 
        ? "No existing events." 
        : sortedEvents.map((e) => "\${e.startTime} - \${e.endTime}: \${e.title}").join("\\n");

      final prompt = '''
You are a highly intelligent scheduling assistant. The user wants to add a new task to their day.
They might ask you to fit a long task into free gaps (e.g., "fit a 3 hour movie in my free time").
Or they might ask you to adjust their schedule or ensure they get 7 hours of sleep.

CURRENT SCHEDULE TODAY:
$scheduleStr

RULES:
1. Find empty gaps between the events in the CURRENT SCHEDULE.
2. If the user's task is longer than any single free gap, split the task into multiple phases across different gaps (e.g., "Watch Movie (Part 1)" and "Watch Movie (Part 2)").
3. IMPORTANT SLEEP CHECK: Analyze the schedule. Ensure the user has at least a continuous 7-hour block for sleep (usually at night, e.g. 11:00 PM to 06:00 AM). If they don't, or if they explicitly ask you to adjust sleep, forcefully ADD a "Sleep" or "Nap" event into the schedule to ensure they get enough rest.
4. Output a valid JSON ARRAY of objects. Each object represents a new event to add.

Format:
[
  {
    "dayOfWeek": "Today", 
    "startTime": "08:00 PM", 
    "endTime": "09:30 PM",
    "title": "Watch Movie (Part 1)",
    "subtitle": "Custom Task",
    "category": "custom"
  },
  {
    "dayOfWeek": "Today", 
    "startTime": "10:30 PM", 
    "endTime": "12:00 AM",
    "title": "Watch Movie (Part 2)",
    "subtitle": "Custom Task",
    "category": "custom"
  }
]

User Request: "$promptText"
Return ONLY the raw JSON array.
''';
      final response = await _chatModel.generateContent([Content.text(prompt)]);
      final jsonStr = _extractJsonPayload(response.text) ?? '[]';
      final decoded = jsonDecode(jsonStr);
      
      if (decoded is! List) {
        return [_fallbackCustomTask(promptText)];
      }

      final List<DailyEvent> newEvents = [];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          newEvents.add(DailyEvent(
            dayOfWeek: item['dayOfWeek'] ?? 'Today',
            startTime: item['startTime'] ?? '12:00 PM',
            endTime: item['endTime'] ?? '01:00 PM',
            title: item['title'] ?? 'Task',
            subtitle: item['subtitle'] ?? 'Custom Task',
            category: item['category'] ?? 'custom',
          ));
        }
      }
      
      if (newEvents.isEmpty) {
        return [_fallbackCustomTask(promptText)];
      }
      return newEvents;
    } catch (e) {
      print('Parse Custom Task Failed: $e');
      return [_fallbackCustomTask(promptText)];
    }
  }

  /// Automatically schedules sleep if it is missing from the day's timetable
  Future<List<DailyEvent>> autoScheduleSleep(List<DailyEvent> existingEvents) async {
    try {
      final sortedEvents = List<DailyEvent>.from(existingEvents);
      final scheduleStr = sortedEvents.isEmpty 
        ? "No existing events." 
        : sortedEvents.map((e) => "\${e.startTime} - \${e.endTime}: \${e.title}").join("\\n");

      final prompt = '''
You are a highly intelligent scheduling assistant focused on the student's health.
The student has NOT scheduled any sleep for today.

CURRENT SCHEDULE TODAY:
$scheduleStr

RULES:
1. Find empty gaps between the events in the CURRENT SCHEDULE.
2. Determine the best time for the student to sleep. They need a minimum of 7 hours.
3. Usually, this means scheduling a large block at night (e.g., 11:00 PM to 06:30 AM). If their schedule blocks the night, find the next best continuous block, or split it into a core sleep block and a nap block.
4. Output a valid JSON ARRAY of objects. Each object represents a sleep event.

Format:
[
  {
    "dayOfWeek": "Today", 
    "startTime": "11:00 PM", 
    "endTime": "06:30 AM",
    "title": "Sleep",
    "subtitle": "Rest and Recovery",
    "category": "sleep"
  }
]

Return ONLY the raw JSON array.
''';
      final response = await _chatModel.generateContent([Content.text(prompt)]);
      final jsonStr = _extractJsonPayload(response.text) ?? '[]';
      final decoded = jsonDecode(jsonStr);
      
      if (decoded is! List) return [];

      final List<DailyEvent> newEvents = [];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          newEvents.add(DailyEvent(
            dayOfWeek: item['dayOfWeek'] ?? 'Today',
            startTime: item['startTime'] ?? '11:00 PM',
            endTime: item['endTime'] ?? '06:30 AM',
            title: item['title'] ?? 'Sleep',
            subtitle: item['subtitle'] ?? 'Rest and Recovery',
            category: item['category'] ?? 'sleep',
          ));
        }
      }
      return newEvents;
    } catch (e) {
      print('Auto Schedule Sleep Failed: $e');
      return [];
    }
  }

  String? _extractJsonPayload(String? responseText) {
    if (responseText == null) return null;

    var text = responseText.trim();
    if (text.isEmpty) return null;

    text = text
        .replaceAll(RegExp(r'^```json\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'^```\s*'), '')
        .replaceAll(RegExp(r'\s*```$'), '')
        .trim();

    final arrayStart = text.indexOf('[');
    final arrayEnd = text.lastIndexOf(']');
    if (arrayStart != -1 && arrayEnd != -1 && arrayEnd > arrayStart) {
      return text.substring(arrayStart, arrayEnd + 1);
    }

    final objectStart = text.indexOf('{');
    final objectEnd = text.lastIndexOf('}');
    if (objectStart != -1 && objectEnd != -1 && objectEnd > objectStart) {
      return text.substring(objectStart, objectEnd + 1);
    }

    return null;
  }

  DailyEvent _fallbackCustomTask(String promptText) {
    final timeMatches = RegExp(
      r'(\d{1,2})(?::(\d{2}))?\s*(am|pm)',
      caseSensitive: false,
    ).allMatches(promptText).toList();

    String formatTime(Match match) {
      final hour = int.parse(match.group(1)!);
      final minute = match.group(2) ?? '00';
      final meridiem = match.group(3)!.toUpperCase();
      return '${hour.toString().padLeft(2, '0')}:$minute $meridiem';
    }

    final startTime = timeMatches.isNotEmpty ? formatTime(timeMatches.first) : '12:00 PM';
    final endTime = timeMatches.length > 1 ? formatTime(timeMatches[1]) : '01:00 PM';

    return DailyEvent(
      dayOfWeek: _inferDayOfWeek(promptText),
      startTime: startTime,
      endTime: endTime,
      title: promptText.trim().isEmpty ? 'Task' : promptText.trim(),
      subtitle: 'Custom Task',
      category: 'custom',
    );
  }

  String _inferDayOfWeek(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('tomorrow')) return 'Tomorrow';
    if (lower.contains('today')) return 'Today';

    const days = <String>[
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    for (final day in days) {
      if (lower.contains(day.toLowerCase())) return day;
    }

    return 'Today';
  }

  Future<String> getGlobalObjective() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/user_goal.txt');
      if (await file.exists()) {
        return await file.readAsString();
      }
    } catch (e) {
      print('Could not read global objective: $e');
    }
    return '';
  }

  /// Sends a query to the LLM augmented with context from the Local Vector DB.
  Future<String> chatWithContext(
    String prompt,
    List<DocumentChunk> contextChunks, {
    List<ChatMessage> history = const [],
    String progressSummary = '',
    String globalObjective = '',
  }) async {
    try {
      String contextString = contextChunks.map((c) => 'From ${c.sourceDocument}:\n${c.text}').join('\n\n---\n\n');
      final historyString = history.isEmpty
          ? ''
          : history
              .map((m) => '${m.isAi ? "Assistant" : "Student"}: ${m.text}')
              .join('\n');
      
      final systemInstruction = '''
You are the semPlanner AI Tutor, an expert and highly encouraging teacher.
Below is context extracted from the student's syllabus or course documents. 
Use this context to understand what the student is studying, their specific course requirements, and the scope of their curriculum.

${globalObjective.isNotEmpty ? 'STUDENT MAIN OBJECTIVE: $globalObjective\n(Instruction: Keep this in mind when generating advice or roadmaps.)' : ''}
${progressSummary.isNotEmpty ? 'CRITICAL PROGRESS CONTEXT:\nThe student has already learned and mastered the following: $progressSummary\nUse this information to heavily tailor your explanations. Do NOT waste time explaining basic concepts they already know. Pick up exactly where they left off and match their competency level.' : ''}

When the student asks a question to learn a topic, teach it to them comprehensively using your vast general knowledge! Do NOT restrict your answers to only what is explicitly written in the syllabus text. The syllabus is just there to guide the depth, context, and focus of your teaching.

CRITICAL FORMATTING RULE: 
The chat interface only supports standard Markdown. It does NOT support LaTeX or math-mode formatting. 
NEVER use \$ or \$\$ for variables, functions, or equations. 
ALWAYS format variables, functions, code snippets, or inline math using standard Markdown backticks (e.g., `variable_name`).

Context from Course Documents:
$contextString
${
  historyString.isNotEmpty
      ? '\n\nRECENT CONVERSATION HISTORY (most recent last):\n$historyString\n(Instruction: Use this conversation history to preserve continuity, answer follow-up questions, and respect corrections made earlier in the chat.)'
      : ''
}
''';
      
      final fullPrompt = "$systemInstruction\n\nStudent Question: $prompt";
      
      final response = await _chatModel.generateContent([Content.text(fullPrompt)]);
      return response.text ?? "Sorry, I couldn't generate a response.";
    } catch (e) {
      throw Exception('Chat Failed: $e');
    }
  }

  /// Uses a multi-step agent loop to generate a robust roadmap for a course
  Future<String> generateAgenticRoadmap(String courseName, List<DocumentChunk> allCourseChunks, {String globalObjective = ''}) async {
    try {
      String contextString = allCourseChunks.map((c) => 'From ${c.sourceDocument}:\n${c.text}').join('\n\n---\n\n');

      // Step 1: Extraction & Synthesis
      final extractionPrompt = '''
You are an expert academic planner. Read the following context extracted from all documents related to the course "$courseName".
Your task is to extract every single topic, module, exam date, and requirement.
Synthesize this into a raw, detailed chronological study outline.
CRITICAL INSTRUCTION: You MUST use the provided Context below to generate the roadmap. Do not make up a generic roadmap if you have context.
${globalObjective.isNotEmpty ? 'STUDENT MAIN OBJECTIVE: $globalObjective\n(Instruction: Ensure the roadmap aligns with this objective, but DO NOT write repetitive motivational text about this goal in the output.)' : ''}

Context:
$contextString
''';
      
      final extractionResponse = await _chatModel.generateContent([Content.text(extractionPrompt)]);
      final draftOutline = extractionResponse.text ?? '';

      // Step 2: Review & Refine
      final refinementPrompt = '''
You are a senior curriculum reviewer. You have been given a raw draft study outline for the course "$courseName".
Your task is to refine this draft into a beautiful, week-by-week Markdown roadmap.
Use bullet points, bold text for key concepts, and ensure the progression is logical and comprehensive.
Do NOT include generic advice; stick strictly to the topics and structure of the course.

Raw Draft Outline:
$draftOutline
''';

      final finalResponse = await _chatModel.generateContent([Content.text(refinementPrompt)]);
      return finalResponse.text ?? "Sorry, I couldn't generate the roadmap.";

    } catch (e) {
      throw Exception('Roadmap Generation Failed: $e');
    }
  }

  /// Suggests a productive activity for a time gap
  Future<String> suggestActivityForGap(int durationMinutes, String globalObjective, List<String> courses) async {
    try {
      final prompt = '''
You are a highly encouraging and smart AI tutor. The student has a free gap of $durationMinutes minutes in their timetable right now.
${globalObjective.isNotEmpty ? 'The student\'s main goal and current level is: $globalObjective' : ''}
${courses.isNotEmpty ? 'The student is currently taking these courses: ${courses.join(', ')}' : ''}

CRITICAL RULES:
1. Provide a highly actionable, specific suggestion for what they can do to be productive right now.
2. If the gap is large (e.g., > 90 minutes), divide the time into 2 or 3 distinct productive phases (e.g., "Phase 1: Deep work on X. Phase 2: Review Y").
3. DO NOT suggest basic or generic things (like "Learn HTML/CSS" or "Read a book") if their goal or courses imply an advanced level. Match their implied skill level.
4. Keep the entire response concise and scannable (under 4 sentences total). Use bullet points if dividing the gap.
''';
      
      final response = await _chatModel.generateContent([Content.text(prompt)]);
      return response.text?.trim() ?? "Review your notes or catch up on reading.";
    } catch (e) {
      print('Suggest Activity Failed: $e');
      return "Use this time to review your upcoming tasks or take a short break.";
    }
  }

  /// The Background Progress Agent Loop
  Future<void> updateLearningProgress(String courseId, ObjectBoxDB db) async {
    try {
      final courseList = db.store.box<Course>().getAll().where((c) => c.courseId == courseId).toList();
      if (courseList.isEmpty) return;
      final course = courseList.first;

      final messages = db.store.box<ChatMessage>().getAll().where((m) => m.courseId == courseId).toList();
      if (messages.isEmpty) return;
      
      // Sort messages chronologically
      messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      
      // OPTIMIZATION: Only use the last 12 messages to calculate progress
      // This massively reduces token usage over time while keeping the analysis relevant
      final recentMessages = messages.length > 12 ? messages.sublist(messages.length - 12) : messages;
      
      final chatHistory = recentMessages.map((m) => "${!m.isAi ? 'User' : 'AI'}: ${m.text}").join("\n");
      
      final prompt = '''
You are a Progress Tracking Agent for a student taking the course "${course.name}".
Your job is to read the following conversation history and extract their exact learning progress.

Current Progress Summary: ${course.progressSummary.isEmpty ? 'None' : course.progressSummary}
Current Percentage: ${course.progressPercentage}%

CHAT HISTORY:
$chatHistory

Analyze the chat history. What concepts has the student mastered? What do they struggle with?
Update the progress summary to be highly dense and factual. Ensure it describes their exact current competency level.
Also estimate their completion percentage of the course based on their progress (0 to 100).

Return ONLY a raw JSON object with the following structure:
{
  "progressSummary": "string",
  "progressPercentage": number
}
Do not include markdown blocks like ```json.
''';
      
      final response = await _chatModel.generateContent([Content.text(prompt)]);
      if (response.text != null) {
        String jsonStr = response.text!.trim();
        if (jsonStr.startsWith('```json')) {
          jsonStr = jsonStr.substring(7, jsonStr.length - 3).trim();
        } else if (jsonStr.startsWith('```')) {
          jsonStr = jsonStr.substring(3, jsonStr.length - 3).trim();
        }
        
        final Map<String, dynamic> data = jsonDecode(jsonStr);
        course.progressSummary = data['progressSummary'] ?? course.progressSummary;
        course.progressPercentage = (data['progressPercentage'] ?? course.progressPercentage).toDouble();
        
        db.store.box<Course>().put(course);
        print("Updated learning progress for ${course.name}: ${course.progressPercentage}%");
      }
    } catch (e) {
      print("Failed to update learning progress: \$e");
    }
  }
}

