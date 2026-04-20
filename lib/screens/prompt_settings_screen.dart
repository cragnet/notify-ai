import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';

class PromptSettingsScreen extends StatefulWidget {
  const PromptSettingsScreen({super.key});

  @override
  State<PromptSettingsScreen> createState() => _PromptSettingsScreenState();
}

class _PromptSettingsScreenState extends State<PromptSettingsScreen> {
  late TextEditingController _promptController;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _load() {
    final settings = context.read<SettingsProvider>();
    setState(() {
      _promptController = TextEditingController(text: settings.getCustomPrompt());
    });
  }

  Future<void> _save() async {
    final settings = context.read<SettingsProvider>();
    await settings.setCustomPrompt(_promptController.text);
    setState(() => _saved = true);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _saved = false);
    });
  }

  void _resetToDefault() {
    setState(() {
      _promptController.text = SettingsProvider.defaultPrompt;
      _saved = false;
    });
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final isDefault = _promptController.text == SettingsProvider.defaultPrompt;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Prompt'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth > 600;
          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: wide ? constraints.maxWidth * 0.15 : 16,
              vertical: 16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Label('Custom AI Prompt'),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _promptController,
                          maxLines: 10,
                          minLines: 6,
                          decoration: const InputDecoration(
                            hintText: 'Enter your custom prompt...',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                          style: const TextStyle(fontSize: 14, height: 1.5),
                          onChanged: (_) => setState(() => _saved = false),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        isDefault ? 'Using default prompt' : 'Custom prompt active',
                        style: TextStyle(
                          color: isDefault ? Colors.white38 : const Color(0xFF6B9E78),
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (!isDefault)
                      TextButton(
                        onPressed: _resetToDefault,
                        child: const Text('Reset to default'),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saved ? null : _save,
                    icon: _saved
                        ? const Icon(Icons.check, size: 18)
                        : const Icon(Icons.save_outlined, size: 18),
                    label: Text(_saved ? 'Saved' : 'Save prompt'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _saved ? const Color(0xFF6B9E78) : null,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                _Label('Variables'),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _VariableItem('{notifications}', 'The grouped notification content'),
                      const Divider(color: Colors.white10, height: 16),
                      _VariableItem('{app_name}', 'Name of the app that sent the notifications'),
                      const Divider(color: Colors.white10, height: 16),
                      _VariableItem('{count}', 'Number of notifications in the group'),
                      const Divider(color: Colors.white10, height: 16),
                      _VariableItem('{length}', 'Summary length setting (1=brief, 2=balanced, 3=detailed)'),
                      const Divider(color: Colors.white10, height: 16),
                      _VariableItem('{length_instruction}', 'Full length instruction text for the AI'),
                      const Divider(color: Colors.white10, height: 16),
                      _VariableItem('{hint}', 'Concise length hint (e.g., "in one very brief sentence")'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF6B9E78).withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: const Color(0xFF6B9E78), size: 16),
                          const SizedBox(width: 8),
                          Text(
                            'Using with Summary Length',
                            style: TextStyle(
                              color: const Color(0xFF6B9E78),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'By default, custom prompts ignore the Summary Length slider. To use it, include {length_instruction} or {hint} in your prompt.',
                        style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Note: These variables are replaced at runtime with actual values.',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 0, 0),
        child: Text(
          text,
          style: const TextStyle(
            color: Color(0xFF6B9E78),
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      );
}

class _VariableItem extends StatelessWidget {
  final String name;
  final String description;
  const _VariableItem(this.name, this.description);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF2A3A2E),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            name,
            style: const TextStyle(
              color: Color(0xFF6B9E78),
              fontSize: 12,
              fontFamily: 'monospace',
              fontFamilyFallback: ['Courier'],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            description,
            style: const TextStyle(color: Colors.white60, fontSize: 13),
          ),
        ),
      ],
    );
  }
}
