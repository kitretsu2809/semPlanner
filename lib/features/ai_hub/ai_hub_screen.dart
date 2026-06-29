import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:semplanner/core/theme.dart';
import 'package:semplanner/core/providers/app_providers.dart';
import 'package:semplanner/core/models/course.dart';
import 'package:semplanner/core/models/document_chunk.dart';
import 'package:semplanner/core/models/chat_message.dart';
import 'package:semplanner/core/models/daily_event.dart';

class AiHubScreen extends ConsumerStatefulWidget {
  const AiHubScreen({super.key});

  @override
  ConsumerState<AiHubScreen> createState() => _AiHubScreenState();
}

class _AiHubScreenState extends ConsumerState<AiHubScreen> {
  List<Course> _courses = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCourses();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _loadCourses() {
    final db = ref.read(objectBoxProvider);
    setState(() {
      _courses = db.store.box<Course>().getAll();
      _isLoading = false;
    });
  }

  void _clearDatabase() {
    final db = ref.read(objectBoxProvider);
    db.store.box<Course>().removeAll();
    db.store.box<DocumentChunk>().removeAll();
    db.store.box<ChatMessage>().removeAll();
    db.store.box<DailyEvent>().removeAll();
    _loadCourses();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All data and schedules cleared.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('AI Study Hub'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.red),
            tooltip: 'Clear All Data',
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Clear All Documents?'),
                  content: const Text('This will delete all uploaded PDFs, courses, chat history, and your timetable schedules. This cannot be undone.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _clearDatabase();
                      },
                      child: const Text('Delete All', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          const Text(
            'Your Processed Documents',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
          ),
          const SizedBox(height: 16),
          
          if (_courses.isEmpty)
            const Text('No documents uploaded yet. Go to Intake to upload syllabi.', style: TextStyle(color: AppTheme.textLight)),
            


          Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: _buildHubCard(
              context, 
              title: 'General AI Tutor', 
              subtitle: 'Chat about your main goals and general questions', 
              icon: Icons.psychology,
              courseId: 'general_tutor',
            ),
          ),
          
          if (_courses.isNotEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                'Course Documents',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
              ),
            ),

            
          ..._courses
            .where((c) {
              final n = c.name.toLowerCase();
              final id = c.courseId.toLowerCase();
              return !n.contains('timetable') && !n.contains('mess') && 
                     !id.startsWith('timetable') && !id.startsWith('mess');
            })
            .map((course) {
            IconData icon = Icons.book;
            if (course.courseId.startsWith('mess')) icon = Icons.restaurant;
            
            return Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: _buildHubCard(
                context, 
                title: course.name, 
                subtitle: 'Tap to chat with this document', 
                icon: icon,
                courseId: course.courseId,
              ),
            );
          }),
          
          const SizedBox(height: 32),
          
          OutlinedButton.icon(
            onPressed: () {
              context.push('/onboarding/intake');
            },
            icon: const Icon(Icons.add, color: AppTheme.primaryBlue),
            label: const Text('Add New Syllabus/Document', style: TextStyle(color: AppTheme.primaryBlue)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppTheme.primaryBlue),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 2,
        selectedItemColor: AppTheme.primaryBlue,
        unselectedItemColor: AppTheme.textLight,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          if (index == 0) context.go('/dashboard');
          if (index == 1) context.push('/onboarding/intake');
          if (index == 3) context.go('/roadmap');
          // index 2 is Hub
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.add_circle_outline), label: 'Intake'),
          BottomNavigationBarItem(icon: Icon(Icons.hub), label: 'Hub'),
          BottomNavigationBarItem(icon: Icon(Icons.route_outlined), label: 'Roadmap'),
        ],
      ),
    );
  }

  Widget _buildHubCard(BuildContext context, {required String title, required String subtitle, required IconData icon, required String courseId}) {
    return InkWell(
      onTap: () {
        context.push('/chat/$courseId');
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
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
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primaryBlue)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(color: AppTheme.textLight, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppTheme.textLight),
          ],
        ),
      ),
    );
  }
}
