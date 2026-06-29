import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryBlue = Color(0xFF1E1B4B); // Deep blue for headers/cards
  static const Color background = Color(0xFFF8FAFC); // Very light slate
  static const Color cardLight = Color(0xFFEFF6FF); // Light blue tint for cards
  static const Color textDark = Color(0xFF0F172A);
  static const Color textLight = Color(0xFF64748B);
  static const Color mintGreen = Color(0xFFA7F3D0); // For progress/status pills
  static const Color buttonPurple = Color(0xFF4F46E5); 

  static ThemeData get lightTheme {
    return ThemeData(
      scaffoldBackgroundColor: background,
      primaryColor: primaryBlue,
      fontFamily: 'Inter', // Assuming Inter based on clean UI
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        iconTheme: IconThemeData(color: primaryBlue),
        titleTextStyle: TextStyle(
          color: primaryBlue,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: primaryBlue,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: primaryBlue, width: 1.5),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        ),
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(color: primaryBlue, fontSize: 32, fontWeight: FontWeight.bold),
        titleLarge: TextStyle(color: textDark, fontSize: 22, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: textDark, fontSize: 16),
        bodyMedium: TextStyle(color: textLight, fontSize: 14),
      ),
    );
  }
}
