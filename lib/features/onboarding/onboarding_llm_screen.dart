import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:semplanner/core/theme.dart';
import 'package:semplanner/core/providers/app_providers.dart';

class OnboardingLlmScreen extends ConsumerStatefulWidget {
  const OnboardingLlmScreen({super.key});

  @override
  ConsumerState<OnboardingLlmScreen> createState() => _OnboardingLlmScreenState();
}

class _OnboardingLlmScreenState extends ConsumerState<OnboardingLlmScreen> {
  final TextEditingController _keyController = TextEditingController();
  
  String selectedProvider = 'Google Gemini';
  String? selectedModel = 'gemini-1.5-flash';
  
  bool _isFetching = false;
  List<String> availableModels = ['gemini-1.5-flash', 'gemini-1.5-pro', 'gemini-2.0-flash-exp'];

  @override
  void initState() {
    super.initState();
    _loadSavedConfig();
  }

  Future<void> _loadSavedConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final savedKey = prefs.getString('user_api_key') ?? '';
    final savedModel = prefs.getString('user_model');
    final savedProvider = prefs.getString('user_provider') ?? 'Google Gemini';

    if (!mounted) return;

    setState(() {
      _keyController.text = savedKey;
      selectedProvider = savedProvider;
      if (savedModel != null && savedModel.isNotEmpty) {
        selectedModel = savedModel;
        if (!availableModels.contains(savedModel)) {
          availableModels = [savedModel, ...availableModels.where((m) => m != savedModel)];
        }
      }
    });
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _fetchModels() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter an API key first')));
      return;
    }

    setState(() {
      _isFetching = true;
    });

    try {
      if (selectedProvider == 'Google Gemini') {
        final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?key=$key');
        final response = await http.get(url);
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final models = (data['models'] as List).map((m) => m['name'] as String).toList();
          
          // Filter out purely embedding/tuning models to only show generative chat models
          final chatModels = models
              .where((m) => m.contains('gemini') && !m.contains('embedding') && !m.contains('vision'))
              .map((m) => m.replaceAll('models/', '')) // Remove the 'models/' prefix
              .toList();
              
          setState(() {
            if (chatModels.isNotEmpty) {
              availableModels = chatModels;
              selectedModel = availableModels.first;
            }
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Models fetched successfully!')));
          }
        } else {
          final data = jsonDecode(response.body);
          throw Exception(data['error']['message'] ?? 'Invalid API Key');
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('OpenAI is not wired up in this build. Please use Google Gemini.')),
          );
        }
        return;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to fetch models: $e')));
      }
    } finally {
      setState(() {
        _isFetching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Initialize AI'),
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
                      'Bring Your Own Key (BYOK)',
                      style: TextStyle(
                        color: AppTheme.primaryBlue,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'To keep this app free, you power it using your own API key. Your key is only saved locally on your device.',
                      style: TextStyle(color: AppTheme.textLight, fontSize: 16),
                    ),
                    const SizedBox(height: 32),
                    
                  const Text('1. Select Provider', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildProviderCard('Google Gemini', isSelected: selectedProvider == 'Google Gemini'),
                      const SizedBox(width: 16),
                        _buildProviderCard('OpenAI', isSelected: selectedProvider == 'OpenAI'),
                    ],
                  ),
                    
                    const SizedBox(height: 24),
                    
                    const Text('2. Enter API Key', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _keyController,
                      decoration: InputDecoration(
                        hintText: 'Paste your secret API key here',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        suffixIcon: IconButton(
                          icon: _isFetching 
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.download, color: AppTheme.primaryBlue),
                          onPressed: _isFetching ? null : _fetchModels,
                          tooltip: 'Fetch Available Models',
                        ),
                      ),
                      onSubmitted: (_) => _fetchModels(),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Click the download icon inside the text box to fetch available models for your key.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),

                    const SizedBox(height: 24),
                    
                    if (availableModels.isNotEmpty) ...[
                      const Text('3. Select Model', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedModel,
                            isExpanded: true,
                            items: availableModels.map((model) {
                              return DropdownMenuItem(
                                value: model,
                                child: Text(model),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => selectedModel = val);
                            },
                          ),
                        ),
                      ),
                    ],
                    
                    const Spacer(),
                    
                    ElevatedButton(
                      onPressed: () async {
                      if (_keyController.text.trim().isNotEmpty) {
                        final key = _keyController.text.trim();
                          
                          try {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString('user_api_key', key);
                          if (selectedModel != null) {
                            await prefs.setString('user_model', selectedModel!);
                          }
                          await prefs.setString('user_provider', selectedProvider);
                        } catch (e) {
                          print('Error saving keys: $e');
                        }

                          ref.read(llmConfigProvider.notifier).updateConfig(
                            apiKey: key,
                            chatModel: selectedModel,
                          );
                          if (context.mounted) context.push('/onboarding/goals');
                        } else {
                           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter an API key')));
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.buttonPurple,
                        foregroundColor: Colors.white,
                        side: BorderSide.none,
                      ),
                      child: const Text('Connect & Continue'),
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

  Widget _buildProviderCard(String name, {required bool isSelected}) {
    return Expanded(
      child: InkWell(
        onTap: () {
          if (name == 'OpenAI') {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('OpenAI support is coming soon. Google Gemini is enabled now.')),
            );
            return;
          }
          setState(() {
            selectedProvider = name;
            availableModels = [];
            selectedModel = null;
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryBlue : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSelected ? AppTheme.primaryBlue : Colors.grey.shade300),
          ),
          child: Text(
            name,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.white : AppTheme.textDark,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
