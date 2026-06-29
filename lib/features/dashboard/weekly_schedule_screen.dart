import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:semplanner/core/theme.dart';
import 'package:semplanner/core/models/daily_event.dart';
import 'package:semplanner/core/providers/app_providers.dart';

class WeeklyScheduleScreen extends ConsumerStatefulWidget {
  const WeeklyScheduleScreen({super.key});

  @override
  ConsumerState<WeeklyScheduleScreen> createState() => _WeeklyScheduleScreenState();
}

class _WeeklyScheduleScreenState extends ConsumerState<WeeklyScheduleScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  Map<String, List<DailyEvent>> _weeklyEvents = {};

  @override
  void initState() {
    super.initState();
    // Default to today's tab
    int todayIndex = DateTime.now().weekday - 1;
    _tabController = TabController(length: 7, vsync: this, initialIndex: todayIndex);
    _loadAllEvents();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  int _parseTime(String timeStr) {
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

  void _loadAllEvents() {
    final db = ref.read(objectBoxProvider);
    final allEvents = db.store.box<DailyEvent>().getAll();

    Map<String, List<DailyEvent>> expanded = {
      for (var day in _days) day: []
    };

    final todayStr = _days[DateTime.now().weekday - 1].toLowerCase();

    for (var event in allEvents) {
      final dayRaw = event.dayOfWeek.toLowerCase();
      
      for (int i = 0; i < 7; i++) {
        final dStr = _days[i].toLowerCase();
        final isWeekday = i < 5;
        
        bool matchesDay = false;
        if (dayRaw.contains(dStr) || dStr.contains(dayRaw)) {
          matchesDay = true;
        } else if (dayRaw == 'today' && dStr == todayStr) {
          matchesDay = true;
        } else if (dayRaw.contains('everyday') || dayRaw.contains('daily') || dayRaw.isEmpty) {
          matchesDay = true;
        } else if (isWeekday && dayRaw.contains('weekday')) {
          matchesDay = true;
        } else if (!isWeekday && dayRaw.contains('weekend')) {
          matchesDay = true;
        }

        if (matchesDay) {
          expanded[_days[i]]!.add(event);
        }
      }
    }

    // Sort each day chronologically
    for (var day in _days) {
      expanded[day]!.sort((a, b) => _parseTime(a.startTime).compareTo(_parseTime(b.startTime)));
    }

    setState(() {
      _weeklyEvents = expanded;
    });
  }

  Widget _buildEventCard(DailyEvent event) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          )
        ],
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
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.cardLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  event.category.toUpperCase(),
                  style: const TextStyle(
                    color: AppTheme.primaryBlue,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            event.title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
          if (event.subtitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              event.subtitle,
              style: const TextStyle(fontSize: 13, color: AppTheme.textLight),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Weekly Schedule'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: AppTheme.primaryBlue,
          unselectedLabelColor: AppTheme.textLight,
          indicatorColor: AppTheme.primaryBlue,
          tabs: _days.map((day) => Tab(text: day)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _days.map((day) {
          final events = _weeklyEvents[day] ?? [];
          if (events.isEmpty) {
            return const Center(
              child: Text(
                'No events scheduled.',
                style: TextStyle(color: AppTheme.textLight),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: events.length,
            itemBuilder: (context, index) {
              return _buildEventCard(events[index]);
            },
          );
        }).toList(),
      ),
    );
  }
}
