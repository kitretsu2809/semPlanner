import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:semplanner/core/models/course.dart';
import 'package:semplanner/core/providers/app_providers.dart';
import 'package:semplanner/core/theme.dart';

class RoadmapScreen extends ConsumerStatefulWidget {
  const RoadmapScreen({super.key});

  @override
  ConsumerState<RoadmapScreen> createState() => _RoadmapScreenState();
}

class _RoadmapScreenState extends ConsumerState<RoadmapScreen> {
  List<Course> _courses = [];

  @override
  void initState() {
    super.initState();
    _loadCourses();
  }

  void _loadCourses() {
    final db = ref.read(objectBoxProvider);
    setState(() {
      _courses = db.store.box<Course>().getAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Roadmaps'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.primaryBlue),
            onPressed: _loadCourses,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Study Roadmaps',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
          ),
          const SizedBox(height: 8),
          const Text(
            'Pick a course, then generate a syllabus-based roadmap or keep chatting with your document.',
            style: TextStyle(color: AppTheme.textLight),
          ),
          const SizedBox(height: 24),
          if (_courses.isEmpty)
            const Text(
              'No courses yet. Go to Intake and upload your syllabi first.',
              style: TextStyle(color: AppTheme.textLight),
            ),
          ..._courses
            .where((c) {
              final n = c.name.toLowerCase();
              final id = c.courseId.toLowerCase();
              return !n.contains('timetable') && !n.contains('mess') && 
                     !id.startsWith('timetable') && !id.startsWith('mess');
            })
            .map(
            (course) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _RoadmapCard(
                course: course,
                onOpenChat: () => context.push('/chat/${course.courseId}'),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 3,
        selectedItemColor: AppTheme.primaryBlue,
        unselectedItemColor: AppTheme.textLight,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          if (index == 0) context.go('/dashboard');
          if (index == 1) context.push('/onboarding/intake');
          if (index == 2) context.go('/hub');
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.add_circle_outline), label: 'Intake'),
          BottomNavigationBarItem(icon: Icon(Icons.hub_outlined), label: 'Hub'),
          BottomNavigationBarItem(icon: Icon(Icons.route_outlined), label: 'Roadmap'),
        ],
      ),
    );
  }
}

class _RoadmapCard extends StatelessWidget {
  final Course course;
  final VoidCallback onOpenChat;

  const _RoadmapCard({
    required this.course,
    required this.onOpenChat,
  });

  @override
  Widget build(BuildContext context) {
    final icon = course.courseId.startsWith('mess')
        ? Icons.restaurant
        : course.courseId.startsWith('timetable')
            ? Icons.calendar_month
            : Icons.book;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.cardLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.primaryBlue),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  course.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primaryBlue),
                ),
                const SizedBox(height: 4),
                Text(
                  course.scheduleInfo.isNotEmpty ? course.scheduleInfo : 'Tap to generate a roadmap for this course',
                  style: const TextStyle(color: AppTheme.textLight, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: onOpenChat,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryBlue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Open'),
          ),
        ],
      ),
    );
  }
}
