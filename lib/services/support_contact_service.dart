import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/whatsapp_icon.dart';

class SupportContactService {
  SupportContactService._();

  static const primaryPhone = '0902 166 1674';
  static const secondaryPhone = '09079343919';
  static const whatsappPhone = '2349021661674';
  static const email = 'scholaxia23@gmail.com';

  static Future<void> openWhatsApp() async {
    final message = Uri.encodeComponent(
      'Hello Scholaxia, I need help with the app.',
    );
    await _launch(Uri.parse('https://wa.me/$whatsappPhone?text=$message'));
  }

  static Future<void> call(String phone) =>
      _launch(Uri(scheme: 'tel', path: phone.replaceAll(' ', '')));

  static Future<void> sendEmail() => _launch(
    Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: {'subject': 'Scholaxia support'},
    ),
  );

  static Future<void> _launch(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw StateError('Could not open $uri');
    }
  }
}

class ContactScholaxiaScreen extends StatelessWidget {
  const ContactScholaxiaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Contact us')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'We are here to help',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Call, email, or chat with a Scholaxia representative.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          _ContactCard(
            leading: const WhatsAppIcon(size: 40),
            title: 'WhatsApp',
            subtitle: SupportContactService.primaryPhone,
            onTap: SupportContactService.openWhatsApp,
          ),
          _ContactCard(
            icon: Icons.phone_rounded,
            color: const Color(0xFF7C3AED),
            title: 'Support line 1',
            subtitle: SupportContactService.primaryPhone,
            onTap: () =>
                SupportContactService.call(SupportContactService.primaryPhone),
          ),
          _ContactCard(
            icon: Icons.phone_in_talk_rounded,
            color: const Color(0xFF6366F1),
            title: 'Support line 2',
            subtitle: SupportContactService.secondaryPhone,
            onTap: () => SupportContactService.call(
              SupportContactService.secondaryPhone,
            ),
          ),
          _ContactCard(
            icon: Icons.email_rounded,
            color: const Color(0xFF0EA5E9),
            title: 'Email',
            subtitle: SupportContactService.email,
            onTap: SupportContactService.sendEmail,
          ),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    this.icon,
    this.color,
    this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData? icon;
  final Color? color;
  final Widget? leading;
  final String title;
  final String subtitle;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? const Color(0xFF7C3AED);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: leading ??
            CircleAvatar(
              backgroundColor: accent.withValues(alpha: 0.12),
              child: Icon(icon, color: accent),
            ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
        onTap: () async {
          try {
            await onTap();
          } catch (_) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not open this contact.')),
            );
          }
        },
      ),
    );
  }
}
