import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:semplanner/firebase_options.dart';
import 'package:semplanner/core/theme.dart';
import 'package:semplanner/core/router.dart';
import 'package:semplanner/core/db/objectbox_db.dart';
import 'package:semplanner/core/providers/app_providers.dart';
import 'package:semplanner/core/services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  await NotificationService().init();
  
  final objectBoxDB = await ObjectBoxDB.create();

  runApp(
    ProviderScope(
      overrides: [
        objectBoxProvider.overrideWithValue(objectBoxDB),
      ],
      child: const SemPlannerApp(),
    ),
  );
}

class SemPlannerApp extends StatelessWidget {
  const SemPlannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'semPlanner',
      theme: AppTheme.lightTheme,
      routerConfig: goRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
