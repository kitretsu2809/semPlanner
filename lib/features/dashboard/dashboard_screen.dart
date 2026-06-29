import 'package:flutter/material.dart';
import 'dart:io';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:semplanner/core/theme.dart';
import 'package:semplanner/core/models/daily_event.dart';
import 'package:semplanner/core/models/course.dart';
import 'package:semplanner/core/providers/app_providers.dart';
import 'package:semplanner/core/services/notification_service.dart';
import 'package:semplanner/features/dashboard/weekly_schedule_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> with WidgetsBindingObserver {
  List<DailyEvent> _events = [];
  String _searchQuery = '';
  final Map<String, String> _gapSuggestions = {};
  final Map<String, bool> _isLoadingGap = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService().requestPermissions();
      _loadGapSuggestions();
      _loadEvents();
    });
  }

  Future<void> _loadGapSuggestions() async {
    final prefs = await SharedPreferences.getInstance();
    final dateKey = 'gap_suggestions_${_formatToday()}';
    final data = prefs.getString(dateKey);
    if (data != null) {
      final map = jsonDecode(data) as Map<String, dynamic>;
      setState(() {
        _gapSuggestions.addAll(map.cast<String, String>());
      });
    }
  }

  Future<void> _saveGapSuggestion(String groupKey, String suggestion) async {
    final prefs = await SharedPreferences.getInstance();
    final dateKey = 'gap_suggestions_${_formatToday()}';
    
    final allKeys = prefs.getKeys();
    for (final k in allKeys) {
      if (k.startsWith('gap_suggestions_') && k != dateKey) {
        prefs.remove(k);
      }
    }
    
    _gapSuggestions[groupKey] = suggestion;
    await prefs.setString(dateKey, jsonEncode(_gapSuggestions));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadEvents();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String _getDayOfWeekString(int weekday) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return days[weekday - 1];
  }

  void _loadEvents() {
    final db = ref.read(objectBoxProvider);
    final todayStr = _getDayOfWeekString(DateTime.now().weekday).toLowerCase();
    
    setState(() {
      final allEvents = db.store.box<DailyEvent>().getAll();
      
      // Only show events meant for today (or everyday/daily/unspecified/weekday logic)
      final todayEvents = allEvents.where((e) {
        final day = e.dayOfWeek.toLowerCase();
        final now = DateTime.now();
        final isWeekday = now.weekday >= 1 && now.weekday <= 5;
        
        return day.contains(todayStr) || 
               todayStr.contains(day) ||
               day == 'today' ||
               day.contains('everyday') || 
               day.contains('daily') || 
               (isWeekday && day.contains('weekday')) ||
               (!isWeekday && day.contains('weekend')) ||
               day.isEmpty;
      }).toList();

      // Sort chronologically using integer minutes from midnight
      todayEvents.sort((a, b) => _parseTime(a.startTime).compareTo(_parseTime(b.startTime)));
      _events = todayEvents;
      
      _scheduleNotificationsForToday();
      _checkAndAutoScheduleSleep();
    });
  }
  
  bool _isAutoSchedulingSleep = false;
  Future<void> _checkAndAutoScheduleSleep() async {
    if (_isAutoSchedulingSleep) return;
    
    // Check if sleep is already scheduled today
    final hasSleep = _events.any((e) => e.title.toLowerCase().contains('sleep') || e.category.toLowerCase().contains('sleep') || e.title.toLowerCase().contains('nap'));
    if (hasSleep) return;

    _isAutoSchedulingSleep = true;
    final aiService = ref.read(aiServiceProvider);
    if (aiService == null) {
      _isAutoSchedulingSleep = false;
      return;
    }

    try {
      final sleepEvents = await aiService.autoScheduleSleep(_events);
      if (sleepEvents.isNotEmpty && mounted) {
        final db = ref.read(objectBoxProvider);
        db.store.box<DailyEvent>().putMany(sleepEvents);
        _loadEvents(); // Reload to show the new sleep events
      }
    } catch (e) {
      print('Auto-schedule sleep failed: $e');
    } finally {
      _isAutoSchedulingSleep = false;
    }
  }

  Future<void> _scheduleNotificationsForToday() async {
    final notificationService = NotificationService();
    await notificationService.cancelAllNotifications();

    final now = DateTime.now();
    for (int i = 0; i < _events.length; i++) {
      final event = _events[i];
      final minutesFromMidnight = _parseTime(event.startTime);
      
      // Calculate exact DateTime for this event today
      final eventTime = DateTime(
        now.year, now.month, now.day, 
        minutesFromMidnight ~/ 60, 
        minutesFromMidnight % 60
      );
      
      // Schedule 12 minutes before
      final notifyTime = eventTime.subtract(const Duration(minutes: 12));
      
      if (notifyTime.isAfter(now)) {
        await notificationService.scheduleNotification(
          id: i, // Unique ID per event today
          title: 'Upcoming: ${event.title}',
          body: 'Starts in 12 minutes at ${event.startTime}',
          scheduledTime: notifyTime,
        );
      }
    }
  }

  List<DailyEvent> _filteredEvents() {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _events;
    return _events.where((event) {
      return event.title.toLowerCase().contains(query) ||
          event.subtitle.toLowerCase().contains(query) ||
          event.category.toLowerCase().contains(query) ||
          event.dayOfWeek.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _showSearchDialog() async {
    final controller = TextEditingController(text: _searchQuery);
    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Search Timetable'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'Search events, titles, or mess timings',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() => _searchQuery = '');
              },
              child: const Text('Clear'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() => _searchQuery = controller.text.trim());
                Navigator.pop(ctx);
              },
              child: const Text('Search'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showAddTaskDialog() async {
    final TextEditingController controller = TextEditingController();
    bool isProcessing = false;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('Add Smart Task', style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Just type what you want to do and the AI will schedule it.', style: TextStyle(color: AppTheme.textLight, fontSize: 14)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      hintText: 'e.g., "Remember me tomorrow at 8 pm to go to department"',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    maxLines: 2,
                  ),
                  if (isProcessing) ...[
                    const SizedBox(height: 16),
                    const CircularProgressIndicator(color: AppTheme.primaryBlue),
                  ]
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: AppTheme.textLight)),
                ),
                ElevatedButton(
                  onPressed: isProcessing ? null : () async {
                    if (controller.text.trim().isEmpty) return;
                    setStateDialog(() => isProcessing = true);
                    
                    final aiService = ref.read(aiServiceProvider);
                    final db = ref.read(objectBoxProvider);
                    
                    if (aiService != null) {
                      try {
                        final events = await aiService.parseCustomTask(controller.text.trim(), _events);
                        if (events.isNotEmpty) {
                          db.store.box<DailyEvent>().putMany(events);
                          _loadEvents();
                        } else {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to parse task.')));
                          }
                        }
                      } catch (e) {
                         if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                          }
                      }
                    }
                    
                    if (context.mounted) Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Schedule'),
                ),
              ],
            );
          }
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final userName = user?.displayName?.split(' ').first ?? 'Student';
    final filteredEvents = _filteredEvents();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: const Icon(Icons.menu_book, color: AppTheme.primaryBlue),
        title: const Text('semPlanner'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_view_week, color: AppTheme.primaryBlue),
            tooltip: 'View Weekly Schedule',
            onPressed: () {
              context.push('/weekly');
            },
          ),
          IconButton(
            icon: const Icon(Icons.search, color: AppTheme.primaryBlue),
            onPressed: _showSearchDialog,
          ),
          IconButton(
            icon: const CircleAvatar(
              radius: 14,
              backgroundColor: AppTheme.cardLight,
              child: Icon(Icons.person, size: 18, color: AppTheme.primaryBlue),
            ),
            onPressed: () {
              context.push('/profile');
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        selectedItemColor: AppTheme.primaryBlue,
        unselectedItemColor: AppTheme.textLight,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          if (index == 1) context.push('/onboarding/intake');
          if (index == 2) context.go('/hub');
          if (index == 3) context.go('/roadmap');
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_circle_outline),
            label: 'Intake',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.hub_outlined), label: 'Hub'),
          BottomNavigationBarItem(
            icon: Icon(Icons.route_outlined),
            label: 'Roadmap',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          Text(
            'Hello, $userName',
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryBlue,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your intellectual itinerary is set for ${_formatToday()}.',
            style: const TextStyle(fontSize: 16, color: AppTheme.textLight),
          ),
          const SizedBox(height: 32),

          // Timeline Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),

              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Today\'s Timetable',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryBlue,
                      ),
                    ),
                    Text(
                      'View Week',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.buttonPurple,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                
                if (_events.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24.0),
                    child: Center(
                      child: Text(
                        'No events extracted yet. Upload a timetable!', 
                        style: TextStyle(color: AppTheme.textLight)
                      ),
                    ),
                  ),

                if (filteredEvents.isNotEmpty) 
                  SizedBox(
                    height: 400,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _buildGroupedTimeline(filteredEvents),
                      ),
                    ),
                  ),
                if (filteredEvents.isEmpty && _events.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24.0),
                    child: Center(
                      child: Text(
                        'No events match your search.',
                        style: TextStyle(color: AppTheme.textLight),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Goal Progress Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: FutureBuilder<String>(
              future: _readSavedGoals(),
              builder: (context, snapshot) {
                final rawGoals = snapshot.data?.trim() ?? '';
                final goals = rawGoals.isEmpty
                    ? <String>[]
                    : rawGoals.split('\n').where((g) => g.trim().isNotEmpty).toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.stars, color: AppTheme.textDark),
                        const SizedBox(width: 8),
                        const Text(
                          'Learning Progress',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (goals.isNotEmpty) ...[
                      const Text('Main Objectives', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
                      const SizedBox(height: 4),
                      Text(
                        goals.first,
                        style: const TextStyle(fontSize: 14, color: AppTheme.textLight),
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                    ],
                    const Text('Course Competency', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
                    const SizedBox(height: 12),
                    StreamBuilder(
                      stream: ref.read(objectBoxProvider).store.box<Course>().query().watch(triggerImmediately: true),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const SizedBox();
                        
                        final courses = snapshot.data!.find()
                          .where((c) {
                             final n = c.name.toLowerCase();
                             final id = c.courseId.toLowerCase();
                             return !n.contains('timetable') && !n.contains('mess') && 
                                    !id.startsWith('timetable') && !id.startsWith('mess');
                          })
                          .toList();

                        if (courses.isEmpty) {
                          return const Text(
                            'No courses added yet.',
                            style: TextStyle(color: AppTheme.textLight),
                          );
                        }

                        return Column(
                          children: courses.map((course) {
                            return Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(course.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                Text('${course.progressPercentage.toStringAsFixed(0)}%', style: const TextStyle(color: AppTheme.buttonPurple, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: course.progressPercentage / 100.0,
                                backgroundColor: AppTheme.cardLight,
                                color: AppTheme.primaryBlue,
                                minHeight: 8,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (course.progressSummary.isNotEmpty)
                              Text(
                                course.progressSummary,
                                style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
                              )
                            else
                              const Text(
                                'No learning data yet. Chat with the tutor to build your profile!',
                                style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
                              ),
                          ],
                        ),
                      );
                    }).toList(),
                    );
                  },
                ),
              ],
            );
          },
        ),
          ),

          const SizedBox(height: 24),

          // Next AI Session Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.auto_awesome, color: Colors.white70, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'NEXT AI TUTOR SESSION',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Starts in 45 mins',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Topic: Recursive Backtracking Patterns',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 24),
                  ElevatedButton.icon(
                  onPressed: () => context.go('/roadmap'),
                  icon: const Icon(
                    Icons.description,
                    color: AppTheme.primaryBlue,
                  ),
                  label: const Text(
                    'Prepare Materials',
                    style: TextStyle(
                      color: AppTheme.primaryBlue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_events.isNotEmpty)
            _buildDynamicMessTimings(),

          const SizedBox(height: 24),

          // Daily Inspiration Card
          Container(
            height: 160,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              image: const DecorationImage(
                image: NetworkImage('https://images.unsplash.com/photo-1518770660439-4636190af475?auto=format&fit=crop&q=80'),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(Colors.black54, BlendMode.darken),
              ),
            ),
            padding: const EdgeInsets.all(24),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Text(
                      'DAILY INSPIRATION',
                      style: TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 1),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '"Intelligence is the ability to adapt to change."',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontStyle: FontStyle.italic, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                Positioned(
                  bottom: -40,
                  right: -10,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: AppTheme.primaryBlue,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.edit_calendar, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 32),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddTaskDialog,
        backgroundColor: AppTheme.primaryBlue,
        icon: const Icon(Icons.auto_awesome, color: Colors.white),
        label: const Text('Smart Task', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  int _parseTime(String timeStr) {
    // Expected format: "09:00 AM" or "10:30 PM"
    final regex = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)', caseSensitive: false);
    final match = regex.firstMatch(timeStr.trim());
    if (match != null) {
      int hour = int.parse(match.group(1)!);
      int minute = int.parse(match.group(2)!);
      String period = match.group(3)!.toUpperCase();
      
      if (period == 'PM' && hour != 12) hour += 12;
      if (period == 'AM' && hour == 12) hour = 0;
      
      return hour * 60 + minute;
    }
    return 0; // Fallback
  }

  List<Widget> _buildGroupedTimeline([List<DailyEvent>? source]) {
    final events = source ?? _filteredEvents();
    if (events.isEmpty) return [];

    Map<String, List<DailyEvent>> grouped = {};
    for (var ev in events) {
      grouped.putIfAbsent(ev.startTime, () => []).add(ev);
    }
    
    List<Widget> items = [];
    final entries = grouped.entries.toList();
    
    for (int i = 0; i < entries.length; i++) {
      int gap = 0;
      if (i < entries.length - 1) {
        int latestEndMins = 0;
        for (var ev in entries[i].value) {
          int endMins = _parseTime(ev.endTime);
          if (endMins > latestEndMins) latestEndMins = endMins;
        }
        int nextStartMins = _parseTime(entries[i+1].key);
        gap = nextStartMins - latestEndMins;
      }

      items.add(
        _buildTimelineGroup(
          time: entries[i].key,
          events: entries[i].value,
          isActive: i == 0,
          isLast: i == entries.length - 1,
          gapMinutes: gap,
        )
      );
    }
    return items;
  }

  String _formatToday() {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final now = DateTime.now();
    return '${months[now.month - 1]} ${now.day}, ${now.year}';
  }

  Future<String> _readSavedGoals() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/user_goal.txt');
      if (await file.exists()) {
        return await file.readAsString();
      }
    } catch (e) {
      print('Could not read goal file: $e');
    }
    return '';
  }

  Widget _buildTimelineGroup({
    required String time,
    required List<DailyEvent> events,
    bool isActive = false,
    bool isLast = false,
    int gapMinutes = 0,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive ? AppTheme.primaryBlue : Colors.white,
                  border: Border.all(
                    color: isActive
                        ? AppTheme.primaryBlue
                        : Colors.grey.shade300,
                    width: 3,
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2, color: Colors.grey.shade200),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...events.map((e) => _buildEventCard(e, isActive)).toList(),
                  if (gapMinutes >= 60) _buildGapCard(gapMinutes, time),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGapCard(int gapMinutes, String groupKey) {
    final isLoading = _isLoadingGap[groupKey] ?? false;
    final suggestion = _gapSuggestions[groupKey];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.primaryBlue.withOpacity(0.3),
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timer_outlined, color: AppTheme.primaryBlue, size: 16),
              const SizedBox(width: 8),
              Text(
                'Free Gap: ${gapMinutes ~/ 60}h ${gapMinutes % 60}m',
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
              ),
            ],
          ),
          if (suggestion != null) ...[
            const SizedBox(height: 8),
            MarkdownBody(
              data: suggestion,
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(color: AppTheme.textDark, fontSize: 13),
              ),
            ),
          ] else if (isLoading) ...[
            const SizedBox(height: 12),
            const SizedBox(
              height: 16, width: 16, 
              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryBlue)
            ),
          ] else ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 32,
              child: OutlinedButton.icon(
                onPressed: () => _generateSuggestionForGap(gapMinutes, groupKey),
                icon: const Icon(Icons.auto_awesome, size: 14),
                label: const Text('Suggest Activity', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  side: BorderSide(color: AppTheme.primaryBlue.withOpacity(0.5)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ]
        ],
      ),
    );
  }

  Future<void> _generateSuggestionForGap(int gapMinutes, String groupKey) async {
    setState(() => _isLoadingGap[groupKey] = true);
    
    final aiService = ref.read(aiServiceProvider);
    if (aiService == null) {
      setState(() => _isLoadingGap[groupKey] = false);
      return;
    }

    final db = ref.read(objectBoxProvider);
    final courses = db.store.box<Course>().getAll().map((c) => c.name).toList();
    final globalObjective = await _readSavedGoals();
    final suggestion = await aiService.suggestActivityForGap(gapMinutes, globalObjective, courses);

    if (mounted) {
      setState(() {
        _isLoadingGap[groupKey] = false;
      });
      await _saveGapSuggestion(groupKey, suggestion);
    }
  }

  Widget _buildEventCard(DailyEvent event, bool isActive) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isActive ? AppTheme.cardLight : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${event.startTime} - ${event.endTime}',
                style: const TextStyle(
                  color: AppTheme.textLight,
                  fontSize: 12,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.cardLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  event.category.toUpperCase(),
                  style: TextStyle(
                    color: isActive ? AppTheme.textDark : AppTheme.textLight,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (event.category.toLowerCase() == 'custom') ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: () {
                    final db = ref.read(objectBoxProvider);
                    db.store.box<DailyEvent>().remove(event.id);
                    _loadEvents();
                  },
                  child: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            event.title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryBlue,
            ),
          ),
          if (event.subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              event.subtitle,
              style: const TextStyle(
                color: AppTheme.textLight,
                fontSize: 12,
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildDynamicMessTimings() {
    final messEvents = _events.where((e) {
      final t = e.title.toLowerCase();
      final c = e.category.toLowerCase();
      return c.contains('mess') || t.contains('breakfast') || t.contains('lunch') || t.contains('dinner') || t.contains('snack');
    }).toList();
    
    if (messEvents.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.cardLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.restaurant, color: AppTheme.textDark),
              SizedBox(width: 8),
              Text(
                'Mess Timings',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: messEvents.map((e) => _buildMessCard(e)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessCard(DailyEvent event) {
    return Container(
      width: 120,
      margin: const EdgeInsets.only(right: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            event.title.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.textLight,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${event.startTime}',
            style: const TextStyle(
              color: AppTheme.primaryBlue,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
