import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:semplanner/core/theme.dart';

class OnboardingGoalScreen extends StatefulWidget {
  const OnboardingGoalScreen({super.key});

  @override
  State<OnboardingGoalScreen> createState() => _OnboardingGoalScreenState();
}

class _OnboardingGoalScreenState extends State<OnboardingGoalScreen> {
  final TextEditingController _goalController = TextEditingController();
  final List<String> _goals = [];

  @override
  void initState() {
    super.initState();
    _loadSavedGoals();
  }

  Future<void> _loadSavedGoals() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/user_goal.txt');
      if (!await file.exists()) return;
      final text = await file.readAsString();
      final goals = text
          .split('\n')
          .map((g) => g.trim())
          .where((g) => g.isNotEmpty)
          .toList();

      if (!mounted) return;
      setState(() {
        _goals.addAll(goals);
      });
    } catch (e) {
      print('Could not load saved goals: $e');
    }
  }

  Future<void> _saveGoals() async {
    final combined = _goals.join('\n');
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/user_goal.txt');
    await file.writeAsString(combined);
  }

  void _addGoal() {
    final text = _goalController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _goals.add(text);
      _goalController.clear();
    });
    _saveGoals();
  }

  @override
  void dispose() {
    _goalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Your Goal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            tooltip: 'Sign Out',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'What are your main objectives?',
                style: TextStyle(
                  color: AppTheme.primaryBlue,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Add one or more goals. We will use them to personalize your semester plan and AI responses.',
                style: TextStyle(color: AppTheme.textLight, fontSize: 16),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _goalController,
                decoration: InputDecoration(
                  hintText: 'e.g., Master Full-Stack Architecture',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
                onSubmitted: (_) => _addGoal(),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _addGoal,
                icon: const Icon(Icons.add, color: AppTheme.primaryBlue),
                label: const Text('Add Another Goal', style: TextStyle(color: AppTheme.primaryBlue)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.primaryBlue),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 24),
              if (_goals.isNotEmpty) ...[
                const Text(
                  'Saved Goals',
                  style: TextStyle(
                    color: AppTheme.primaryBlue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _goals
                      .map(
                        (goal) => Chip(
                          label: Text(goal),
                          backgroundColor: Colors.white,
                          deleteIcon: const Icon(Icons.close, size: 18),
                          onDeleted: () async {
                            setState(() {
                              _goals.remove(goal);
                            });
                            await _saveGoals();
                          },
                        ),
                      )
                      .toList(),
                ),
              ],
              const Spacer(),
              ElevatedButton(
                onPressed: () async {
                  if (_goalController.text.trim().isNotEmpty) {
                    _addGoal();
                  }
                  await _saveGoals();
                  if (context.mounted) context.push('/onboarding/intake');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.buttonPurple,
                  foregroundColor: Colors.white,
                  side: BorderSide.none,
                ),
                child: const Text('Next: Upload Schedule'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
