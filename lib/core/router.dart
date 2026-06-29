import 'package:go_router/go_router.dart';
import 'package:semplanner/features/dashboard/dashboard_screen.dart';
import 'package:semplanner/features/auth/login_screen.dart';
import 'package:semplanner/features/auth/register_screen.dart';
import 'package:semplanner/features/onboarding/onboarding_llm_screen.dart';
import 'package:semplanner/features/onboarding/onboarding_goal_screen.dart';
import 'package:semplanner/features/onboarding/onboarding_intake_screen.dart';
import 'package:semplanner/features/ai_hub/ai_hub_screen.dart';
import 'package:semplanner/features/ai_hub/chat_roadmap_screen.dart';
import 'package:semplanner/features/roadmap/roadmap_screen.dart';
import 'package:semplanner/features/profile/profile_screen.dart';
import 'package:semplanner/features/dashboard/weekly_schedule_screen.dart';

final goRouter = GoRouter(
  initialLocation: '/login', // Force login screen first while developing
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(
      path: '/onboarding/llm',
      builder: (context, state) => const OnboardingLlmScreen(),
    ),
    GoRoute(
      path: '/onboarding/goals',
      builder: (context, state) => const OnboardingGoalScreen(),
    ),
    GoRoute(
      path: '/onboarding/intake',
      builder: (context, state) => const OnboardingIntakeScreen(),
    ),
    GoRoute(
      path: '/dashboard',
      builder: (context, state) => const DashboardScreen(),
    ),
    GoRoute(
      path: '/hub',
      builder: (context, state) => const AiHubScreen(),
    ),
    GoRoute(
      path: '/chat/:courseId',
      builder: (context, state) => ChatRoadmapScreen(courseId: state.pathParameters['courseId']!),
    ),
    GoRoute(
      path: '/profile',
      builder: (context, state) => const ProfileScreen(),
    ),
    GoRoute(
      path: '/roadmap',
      builder: (context, state) => const RoadmapScreen(),
    ),
    GoRoute(
      path: '/weekly',
      builder: (context, state) => const WeeklyScheduleScreen(),
    ),
  ],
);
