import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../providers/settings_provider.dart';
import 'dart:io';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '';
  String _buildNumber = '';
  String _appName = 'Notify AI';
  String _gitCommit = '...';

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      setState(() {
        _version = info.version;
        _buildNumber = info.buildNumber;
        _appName = info.appName;
      });
    } catch (e) {
      setState(() {
        _version = '1.0.0';
        _buildNumber = '1';
      });
    }
    try {
      final commit = await rootBundle.loadString('assets/commit.txt');
      setState(() {
        _gitCommit = commit.trim();
      });
    } catch (e) {
      setState(() {
        _gitCommit = 'unknown';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFF6B9E78),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.notifications_active,
                  size: 40,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                _appName,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A3A2E),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'v$_version (build $_buildNumber)',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF6B9E78),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            _InfoCard(
              title: 'Git Commit',
              value: _gitCommit,
              icon: Icons.commit,
              onTap: () {
                Clipboard.setData(ClipboardData(text: _gitCommit));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Commit hash copied'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _InfoCard(
              title: 'Platform',
              value: '${Platform.operatingSystem} ${Platform.operatingSystemVersion.split(' ').first}',
              icon: Icons.phone_android,
            ),
            const SizedBox(height: 12),
            _InfoCard(
              title: 'Build',
              value: 'Debug',
              icon: Icons.build,
            ),
            const SizedBox(height: 24),
            const Text(
              'Description',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Notify AI is an Android notification summarisation app that intercepts notifications from selected apps, batches them, sends them to an AI provider for summarisation, and delivers a new notification containing the summary.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white70,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Supported AI Providers',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ProviderItem('Ollama', 'Self-hosted or cloud'),
                  SizedBox(height: 8),
                  _ProviderItem('Google Gemini', 'Cloud API'),
                  SizedBox(height: 8),
                  _ProviderItem('Gemini Nano', 'On-device (Pixel 8+)'),
                  SizedBox(height: 8),
                  _ProviderItem('Claude', 'Anthropic API'),
                  SizedBox(height: 8),
                  _ProviderItem('OpenAI', 'Compatible endpoints'),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Test Notifications',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TestButton(
                    label: 'Single Notification',
                    description: '1 message (test threshold behavior)',
                    icon: Icons.notifications,
                    onTap: () => _sendTestNotifications('single', 1),
                  ),
                  const SizedBox(height: 12),
                  _TestButton(
                    label: 'Single Conversation',
                    description: '3 messages from same chat',
                    icon: Icons.chat_bubble,
                    onTap: () => _sendTestNotifications('single', 3),
                  ),
                  const SizedBox(height: 12),
                  _TestButton(
                    label: 'Multi Conversation',
                    description: '4 messages from different chats',
                    icon: Icons.forum,
                    onTap: () => _sendTestNotifications('multi_conversation', 4),
                  ),
                  const SizedBox(height: 12),
                  _TestButton(
                    label: 'Duplicate Messages',
                    description: '3 identical messages (test dedupe)',
                    icon: Icons.content_copy,
                    onTap: () => _sendTestNotifications('duplicates', 3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendTestNotifications(String testType, int count) async {
    const platform = MethodChannel('com.craigcarroll.notifyai/permissions');
    try {
      await platform.invokeMethod('sendTestNotification', {
        'count': count,
        'packageName': 'com.whatsapp',
        'appName': 'WhatsApp',
        'testType': testType,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sent $count test notifications'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  const _InfoCard({
    required this.title,
    required this.value,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF6B9E78), size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 12, color: Colors.white54)),
                  const SizedBox(height: 2),
                  Text(value, style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            if (onTap != null) const Icon(Icons.copy, color: Colors.white38, size: 16),
          ],
        ),
      ),
    );
  }
}

class _ProviderItem extends StatelessWidget {
  final String name;
  final String subtitle;

  const _ProviderItem(this.name, this.subtitle);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(color: Color(0xFF6B9E78), shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w500)),
              Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.white54)),
            ],
          ),
        ),
      ],
    );
  }
}

class _TestButton extends StatelessWidget {
  final String label;
  final String description;
  final IconData icon;
  final VoidCallback onTap;

  const _TestButton({
    required this.label,
    required this.description,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF2A3A2E),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF6B9E78), size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(description, style: const TextStyle(fontSize: 12, color: Colors.white54)),
                ],
              ),
            ),
            const Icon(Icons.send, color: Color(0xFF6B9E78), size: 18),
          ],
        ),
      ),
    );
  }
}