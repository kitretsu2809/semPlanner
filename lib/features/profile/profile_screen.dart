import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:semplanner/core/theme.dart';
import 'package:semplanner/core/models/course.dart';
import 'package:semplanner/core/providers/app_providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = FirebaseAuth.instance.currentUser;
    final name = user?.displayName ?? 'Student';
    final email = user?.email ?? 'Unknown Email';
    
    final llmConfig = ref.watch(llmConfigProvider);
    final db = ref.read(objectBoxProvider);
    final courseCount = db.store.box<Course>().count();
    final chunkCount = db.chunkBox.count();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Profile'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          const Center(
            child: CircleAvatar(
              radius: 48,
              backgroundColor: AppTheme.cardLight,
              child: Icon(Icons.person, size: 48, color: AppTheme.primaryBlue),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              name,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
            ),
          ),
          Center(
            child: Text(email, style: const TextStyle(color: AppTheme.textLight)),
          ),
          
          const SizedBox(height: 40),
          
          const Text('AI Configuration (BYOK)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
          const SizedBox(height: 16),
          _buildSettingsTile(
            icon: Icons.key,
            title: 'Change LLM API Key',
            subtitle: 'Currently using: ${llmConfig.chatModel}',
            onTap: () => _showLlmEditor(context, ref),
          ),
          _buildSettingsTile(
            icon: Icons.tune,
            title: 'Model Settings',
            subtitle: 'Embedding: ${llmConfig.embeddingModel}',
            onTap: () => _showLlmEditor(context, ref),
          ),

          const SizedBox(height: 32),
          
          const Text('Your Goals', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
          const SizedBox(height: 16),
          FutureBuilder<String>(
            future: _readSavedGoals(),
            builder: (context, snapshot) {
              final goalText = snapshot.data?.trim() ?? '';
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Text(
                  goalText.isEmpty ? 'No goals saved yet. Add them from onboarding or edit them later.' : goalText,
                  style: const TextStyle(color: AppTheme.textDark),
                ),
              );
            },
          ),
          
          const SizedBox(height: 32),
          
          const Text('Data & Cloud', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
          const SizedBox(height: 16),
          _buildSettingsTile(
            icon: Icons.cloud_done,
            title: 'Firebase Backup Status',
            subtitle: 'Local-first app, cloud sync not wired yet',
            onTap: () => _showInfoDialog(context, 'Firebase Backup', 'Cloud backup/sync is not wired in this build yet. Your data is stored locally on the device.'),
          ),
          _buildSettingsTile(
            icon: Icons.storage,
            title: 'Local Vector DB Size',
            subtitle: '$courseCount courses, $chunkCount indexed chunks',
            onTap: () => _showInfoDialog(context, 'Vector DB', '$courseCount courses and $chunkCount document chunks are stored locally.'),
          ),
          
          const SizedBox(height: 48),
          
          OutlinedButton.icon(
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) context.go('/login');
            },
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            label: const Text('Sign Out', style: TextStyle(color: Colors.redAccent)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.redAccent),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Future<String> _readSavedGoals() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/user_goal.txt');
      if (await file.exists()) {
        return await file.readAsString();
      }
    } catch (e) {
      print('Could not read goals: $e');
    }
    return '';
  }

  Future<void> _showLlmEditor(BuildContext context, WidgetRef ref) async {
    final currentConfig = ref.read(llmConfigProvider);
    final keyController = TextEditingController(text: currentConfig.apiKey);
    String selectedProvider = 'Google Gemini';
    String? selectedModel = currentConfig.chatModel;
    bool isFetching = false;
    List<String> modelOptions = currentConfig.chatModel.isNotEmpty
        ? [currentConfig.chatModel]
        : ['gemini-1.5-flash'];

    Future<void> fetchModels(StateSetter setStateDialog) async {
      final key = keyController.text.trim();
      if (key.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter an API key first')));
        return;
      }

      setStateDialog(() => isFetching = true);
      try {
        if (selectedProvider != 'Google Gemini') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('OpenAI is not wired up in this build. Please use Google Gemini.')),
          );
          return;
        }

        final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?key=$key');
        final response = await http.get(url);

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final models = (data['models'] as List).map((m) => m['name'] as String).toList();
          final chatModels = models
              .where((m) => m.contains('gemini') && !m.contains('embedding') && !m.contains('vision'))
              .map((m) => m.replaceAll('models/', ''))
              .toList();

          if (chatModels.isNotEmpty) {
            setStateDialog(() {
              modelOptions = chatModels;
              if (!chatModels.contains(selectedModel)) {
                selectedModel = chatModels.first;
              }
            });
          }
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Models fetched successfully!')));
          }
        } else {
          final data = jsonDecode(response.body);
          throw Exception(data['error']['message'] ?? 'Invalid API Key');
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to fetch models: $e')));
        }
      } finally {
        if (context.mounted) {
          setStateDialog(() => isFetching = false);
        }
      }
    }

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Update LLM Settings'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Provider'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('Google Gemini'),
                            selected: selectedProvider == 'Google Gemini',
                            onSelected: (_) {
                              setStateDialog(() {
                                selectedProvider = 'Google Gemini';
                                modelOptions = currentConfig.chatModel.isNotEmpty ? [currentConfig.chatModel] : ['gemini-1.5-flash'];
                                selectedModel = modelOptions.first;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('OpenAI'),
                            selected: selectedProvider == 'OpenAI',
                            onSelected: (_) {
                              setStateDialog(() => selectedProvider = 'OpenAI');
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('API Key'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: keyController,
                      decoration: InputDecoration(
                        hintText: 'Paste your $selectedProvider API key',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: isFetching ? null : () => fetchModels(setStateDialog),
                          icon: isFetching
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.download),
                          tooltip: 'Fetch Available Models',
                        ),
                      ),
                      obscureText: true,
                      onSubmitted: (_) => fetchModels(setStateDialog),
                    ),
                    const SizedBox(height: 16),
                    const Text('Model'),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: selectedModel,
                      isExpanded: true,
                      items: modelOptions.map((model) => DropdownMenuItem(value: model, child: Text(model))).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setStateDialog(() => selectedModel = value);
                        }
                      },
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final key = keyController.text.trim();
                    if (key.isEmpty) return;
                    if (selectedProvider == 'OpenAI') {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('OpenAI is not wired up in this build. Please use Google Gemini.')),
                      );
                      return;
                    }

                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('user_api_key', key);
                    await prefs.setString('user_model', selectedModel ?? currentConfig.chatModel);
                    await prefs.setString('user_provider', selectedProvider);

                    ref.read(llmConfigProvider.notifier).updateConfig(
                      apiKey: key,
                      chatModel: selectedModel,
                    );

                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('LLM settings updated.')));
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showInfoDialog(BuildContext context, String title, String body) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTile({required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.cardLight,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: AppTheme.primaryBlue),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textDark)),
      subtitle: Text(subtitle, style: const TextStyle(color: AppTheme.textLight)),
      trailing: const Icon(Icons.chevron_right, color: AppTheme.textLight),
      onTap: onTap,
    );
  }
}
