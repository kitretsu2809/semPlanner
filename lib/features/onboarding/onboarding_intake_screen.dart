import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:semplanner/core/theme.dart';
import 'package:semplanner/core/providers/app_providers.dart';
import 'package:semplanner/core/models/document_chunk.dart';
import 'package:semplanner/core/models/course.dart';
import 'package:semplanner/core/models/daily_event.dart';

class OnboardingIntakeScreen extends ConsumerStatefulWidget {
  const OnboardingIntakeScreen({super.key});

  @override
  ConsumerState<OnboardingIntakeScreen> createState() => _OnboardingIntakeScreenState();
}

class _OnboardingIntakeScreenState extends ConsumerState<OnboardingIntakeScreen> {
  bool _isProcessing = false;
  String _statusMessage = '';
  int _filesProcessedCount = 0;
  final TextEditingController _goalController = TextEditingController();

  Future<void> _saveGoal() async {
    final text = _goalController.text.trim();
    if (text.isNotEmpty) {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/user_goal.txt');
      await file.writeAsString(text);
    }
  }

  Future<void> _pickAndProcessFiles(String category) async {
    final aiService = ref.read(aiServiceProvider);
    if (aiService == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('AI Service not initialized. Please go back and enter an API key.')));
      return;
    }

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
        allowMultiple: true,
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _isProcessing = true;
          _statusMessage = 'Reading ${result.files.length} file(s)...';
        });

        final parser = ref.read(pdfParserProvider);
        final db = ref.read(objectBoxProvider);

        for (int f = 0; f < result.files.length; f++) {
          final fileData = result.files[f];
          if (fileData.path == null) continue;
          
          final existingChunks = db.chunkBox.getAll().where((c) => c.sourceDocument == fileData.name).toList();
          if (existingChunks.isNotEmpty) {
            setState(() => _statusMessage = 'Updating existing file ${fileData.name}...');
            for (var chunk in existingChunks) {
              db.chunkBox.remove(chunk.id);
            }
          }

          setState(() => _statusMessage = 'Parsing ${fileData.name} (${f+1}/${result.files.length})');
          
          File file = File(fileData.path!);
          String text = '';
          final ext = file.path.split('.').last.toLowerCase();
          
          if (ext == 'pdf') {
            text = await parser.extractTextFromPdf(file);
          } else if (ext == 'png' || ext == 'jpg' || ext == 'jpeg') {
            final bytes = file.readAsBytesSync();
            final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
            text = await aiService.extractTextFromImage(bytes, mime);
          }
          
          if (text.isEmpty) continue;

          if (category == 'timetable' || category == 'mess') {
            // Clear old events for this category before adding new ones
            final oldEvents = db.store.box<DailyEvent>().getAll().where((e) => e.category == category).toList();
            for (var ev in oldEvents) {
              db.store.box<DailyEvent>().remove(ev.id);
            }
            // Parse specific events into the DB dynamically
            await aiService.extractAndSaveSchedule(category, text, db);
          }

          // 2. SMART COURSE EXTRACTION
          setState(() => _statusMessage = 'Identifying Courses in ${fileData.name}...');
          
          final existingCoursesList = db.store.box<Course>().getAll();
          final existingNames = existingCoursesList.map((c) => c.name).toList();
          
          List<String> courseNames = await aiService.identifyCourses(text, existingNames);
          
          List<String> courseIds = [];
          for (String courseName in courseNames) {
            Course? currentCourse;
            for (var c in existingCoursesList) {
              if (c.name.toLowerCase() == courseName.toLowerCase()) {
                currentCourse = c;
                break;
              }
            }
            
            if (currentCourse == null) {
               String newId = 'course_${DateTime.now().millisecondsSinceEpoch}_${courseIds.length}';
               db.store.box<Course>().put(Course(courseId: newId, name: courseName));
               courseIds.add(newId);
            } else {
               courseIds.add(currentCourse.courseId);
            }
          }

          // 3. CHUNKING & EMBEDDING
          setState(() => _statusMessage = 'Chunking ${fileData.name}...');
          List<String> chunks = parser.chunkText(text);

          for (int i = 0; i < chunks.length; i++) {
            setState(() => _statusMessage = 'Embedding ${fileData.name} (${i + 1}/${chunks.length})...');
            
            List<double> embedding = await aiService.generateEmbedding(chunks[i]);
            
            for (String courseId in courseIds) {
              final docChunk = DocumentChunk(
                text: chunks[i],
                sourceDocument: fileData.name,
                courseId: courseId,
                embedding: embedding,
              );
              db.chunkBox.put(docChunk);
            }
          }
          _filesProcessedCount++;
        }

        setState(() {
          _isProcessing = false;
          _statusMessage = 'Success! Processed $_filesProcessedCount file(s).';
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Processing complete.')));
        }
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Setup Your Schedule'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            tooltip: 'Sign Out',
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Sign Out'),
                  content: const Text('Are you sure you want to sign out?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                    TextButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await FirebaseAuth.instance.signOut();
                        if (context.mounted) context.go('/login');
                      },
                      child: const Text('Sign Out', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Let\'s build your database',
                      style: TextStyle(
                        color: AppTheme.primaryBlue,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _filesProcessedCount > 0 
                        ? '$_filesProcessedCount new files processed and saved locally! You can add more, or finish up.'
                        : 'Upload your class timetable, mess menu, and syllabi. You can select multiple files at once.',
                      style: const TextStyle(color: AppTheme.textLight, fontSize: 16),
                    ),
                    const SizedBox(height: 32),
                    
                    const SizedBox(height: 16),
                    TextField(
                      controller: _goalController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Main Objective / Custom Text (e.g. "I want to focus on backend dev, ignore frontend topics")',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    _buildUploadCard(
                      icon: Icons.calendar_month,
                      title: 'Class Timetable',
                      subtitle: 'Upload PDF or Image',
                      onTap: _isProcessing ? null : () => _pickAndProcessFiles('timetable'),
                    ),
                    const SizedBox(height: 16),
                    _buildUploadCard(
                      icon: Icons.restaurant,
                      title: 'Mess Timings & Menu',
                      subtitle: 'Upload PDF',
                      onTap: _isProcessing ? null : () => _pickAndProcessFiles('mess'),
                    ),
                    const SizedBox(height: 16),
                    _buildUploadCard(
                      icon: Icons.book,
                      title: 'Course Syllabi',
                      subtitle: 'Upload multiple PDFs or Images',
                      onTap: _isProcessing ? null : () => _pickAndProcessFiles('syllabus'),
                    ),
                    
                    const Spacer(),
                    
                    if (_isProcessing)
                      Column(
                        children: [
                          const CircularProgressIndicator(color: AppTheme.primaryBlue),
                          const SizedBox(height: 16),
                          Text(_statusMessage, style: const TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 16),
                        ],
                      ),
                      
                    if (!_isProcessing)
                      ElevatedButton(
                        onPressed: () async {
                          await _saveGoal();
                          if (context.mounted) context.go('/dashboard');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.buttonPurple,
                          foregroundColor: Colors.white,
                          side: BorderSide.none,
                        ),
                        child: Text(_filesProcessedCount > 0 ? 'Finish & Go to Dashboard' : 'Skip & Generate My Semester'),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadCard({required IconData icon, required String title, required String subtitle, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.cardLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: AppTheme.primaryBlue),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.textDark)),
                  Text(subtitle, style: const TextStyle(color: AppTheme.textLight, fontSize: 14)),
                ],
              ),
            ),
            const Icon(Icons.upload_file, color: AppTheme.textLight),
          ],
        ),
      ),
    );
  }
}
