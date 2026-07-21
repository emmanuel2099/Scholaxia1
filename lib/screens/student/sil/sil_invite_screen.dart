import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'sil_models.dart';
import 'sil_widgets.dart';

/// Send Invitation UI for Student / Class / School challenges.
class SilInviteScreen extends StatefulWidget {
  final String mode;
  final SilProfile profile;

  const SilInviteScreen({
    super.key,
    required this.mode,
    required this.profile,
  });

  static Future<void> open(
    BuildContext context, {
    required String mode,
    required SilProfile profile,
  }) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SilInviteScreen(mode: mode, profile: profile),
      ),
    );
  }

  @override
  State<SilInviteScreen> createState() => _SilInviteScreenState();
}

class _SilInviteScreenState extends State<SilInviteScreen> {
  int _who = 0; // 0 anyone, 1 school, 2 class
  bool _sent = false;
  int _inviteCount = 0;
  final _phones = <TextEditingController>[TextEditingController()];

  String get _title {
    switch (widget.mode) {
      case 'class_challenge':
        return 'Class Challenge Invite';
      case 'school_challenge':
        return 'School Challenge Invite';
      default:
        return 'Send Invitation';
    }
  }

  String get _inviteCode {
    final tag = widget.profile.gamerTag
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final code = tag.isEmpty ? 'SCHOLAX' : tag.substring(0, tag.length.clamp(0, 8));
    return 'https://scholaxia.com/invite/$code';
  }

  String get _challengeLabel {
    switch (widget.mode) {
      case 'class_challenge':
        return 'Class Challenge';
      case 'school_challenge':
        return 'School Challenge';
      default:
        return 'Student Challenge';
    }
  }

  @override
  void dispose() {
    for (final c in _phones) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: _inviteCode));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invite link copied')),
    );
  }

  Future<void> _shareWhatsApp() async {
    final text = Uri.encodeComponent(
      'Join me on Scholaxia Intellect League for $_challengeLabel! $_inviteCode',
    );
    final uri = Uri.parse('https://wa.me/?text=$text');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      await _copyLink();
    }
  }

  void _send() {
    final filled = _phones.where((c) => c.text.trim().isNotEmpty).length;
    setState(() {
      _sent = true;
      _inviteCount = filled > 0 ? filled : 2;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF111827),
        title: Text(
          _sent ? 'Invitation Sent' : _title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        actions: [
          if (!_sent)
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.person_add_alt_1_rounded),
            ),
        ],
      ),
      body: _sent ? _sentBody() : _composeBody(),
    );
  }

  Widget _composeBody() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            children: [
              _heroBanner(),
              const SizedBox(height: 18),
              const Text('Invite via',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: Color(0xFF111827))),
              const SizedBox(height: 10),
              Row(
                children: [
                  _viaBtn(Icons.chat_rounded, 'WhatsApp', const Color(0xFF22C55E),
                      _shareWhatsApp),
                  _viaBtn(Icons.link_rounded, 'Copy Link', SilColors.purple,
                      _copyLink),
                  _viaBtn(Icons.ios_share_rounded, 'Share', const Color(0xFF2563EB),
                      _copyLink),
                  _viaBtn(Icons.qr_code_2_rounded, 'QR Code',
                      const Color(0xFFF59E0B), () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('QR invite coming soon')),
                    );
                  }),
                ],
              ),
              const SizedBox(height: 18),
              const Text('Invite by Phone Number',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: Color(0xFF111827))),
              const SizedBox(height: 10),
              ...List.generate(_phones.length, (i) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _phoneField(_phones[i]),
                );
              }),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(
                      () => _phones.add(TextEditingController())),
                  child: const Text('+ Add Another Number',
                      style: TextStyle(
                          color: SilColors.purple,
                          fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(height: 8),
              const Text('Invite by Link',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: Color(0xFF111827))),
              const SizedBox(height: 4),
              Text('Share your unique invitation link with friends.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _inviteCode,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _copyLink,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SilColors.purple,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Copy',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text('Anyone with this link can sign up.',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
              const SizedBox(height: 16),
              const Text('Who can you invite?',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: Color(0xFF111827))),
              const SizedBox(height: 10),
              Row(
                children: [
                  _whoCard(
                    0,
                    Icons.people_alt_rounded,
                    'Anyone',
                    'Anyone can join with your link.',
                  ),
                  const SizedBox(width: 8),
                  _whoCard(
                    1,
                    Icons.account_balance_rounded,
                    'Same School',
                    'Students from your school only.',
                  ),
                  const SizedBox(width: 8),
                  _whoCard(
                    2,
                    Icons.class_rounded,
                    'Same Class',
                    'Students from your class only.',
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: SilColors.purpleSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.card_giftcard_rounded,
                        color: SilColors.purple, size: 28),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'You and your friend will both get 50 coins when they join!',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: Color(0xFF111827),
                          height: 1.35,
                        ),
                      ),
                    ),
                    Icon(Icons.monetization_on_rounded,
                        color: Color(0xFFFBBF24), size: 28),
                  ],
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _send,
                icon: const Icon(Icons.send_rounded),
                label: const Text('Send Invitation',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: SilColors.purple,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _heroBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFF2E1065), Color(0xFF5B21B6), Color(0xFF6A5AE0)],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Invite Friends to $_challengeLabel',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Invite your friends to join the league and learn, compete and win together!',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.88),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.mail_outline_rounded,
                    color: Color(0xFFFBBF24), size: 36),
              ),
              const Positioned(
                right: -2,
                top: -2,
                child: Icon(Icons.send_rounded,
                    color: Colors.white70, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _viaBtn(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                children: [
                  Icon(icon, color: color, size: 24),
                  const SizedBox(height: 6),
                  Text(label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _phoneField(TextEditingController ctrl) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          const Text('🇳🇬', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 6),
          const Text('+234',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          Container(
            width: 1,
            height: 22,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            color: const Color(0xFFE5E7EB),
          ),
          Expanded(
            child: TextField(
              controller: ctrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                hintText: 'Enter phone number',
                border: InputBorder.none,
              ),
            ),
          ),
          const Icon(Icons.person_add_alt_rounded,
              color: SilColors.purple, size: 20),
        ],
      ),
    );
  }

  Widget _whoCard(int i, IconData icon, String title, String sub) {
    final on = _who == i;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _who = i),
        child: Container(
          height: 120,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: on ? SilColors.purple : const Color(0xFFE5E7EB),
              width: on ? 1.8 : 1,
            ),
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: SilColors.purple, size: 22),
                  const Spacer(),
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 12)),
                  const SizedBox(height: 2),
                  Text(sub,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 9,
                          height: 1.25)),
                ],
              ),
              if (on)
                const Positioned(
                  right: 0,
                  top: 0,
                  child: Icon(Icons.check_circle_rounded,
                      color: SilColors.purple, size: 18),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sentBody() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const SizedBox(height: 12),
        Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: SilColors.purpleSoft,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(Icons.mail_rounded,
                    color: SilColors.purple, size: 56),
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Color(0xFF22C55E),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_rounded,
                      color: Colors.white, size: 22),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Invitation Sent!',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Your invitation has been sent successfully.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
        const SizedBox(height: 20),
        _summaryRow(Icons.send_rounded, SilColors.purpleSoft, SilColors.purple,
            'Invitation sent to $_inviteCount Friends'),
        _summaryRow(Icons.link_rounded, const Color(0xFFDCFCE7),
            const Color(0xFF16A34A), 'Your invite link is ready. Copied to clipboard'),
        _summaryRow(Icons.monetization_on_rounded, const Color(0xFFFFF7ED),
            const Color(0xFFEA580C),
            'You\'ll earn 50 Coins once they join'),
        const SizedBox(height: 18),
        const Text('Invite More Friends',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 4),
        Text('The more friends you invite, the more coins you earn!',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _roundShare(Icons.chat_rounded, const Color(0xFF22C55E),
                _shareWhatsApp),
            _roundShare(Icons.link_rounded, SilColors.purple, _copyLink),
            _roundShare(Icons.ios_share_rounded, const Color(0xFF2563EB),
                _copyLink),
            _roundShare(Icons.more_horiz_rounded, const Color(0xFF6B7280),
                () {}),
          ],
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: () => setState(() => _sent = false),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Invite More Friends',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            style: ElevatedButton.styleFrom(
              backgroundColor: SilColors.purple,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Go to Home',
              style: TextStyle(
                  color: SilColors.purple, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }

  Widget _summaryRow(
      IconData icon, Color bg, Color fg, String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(icon, color: fg, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Color(0xFF111827))),
          ),
        ],
      ),
    );
  }

  Widget _roundShare(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color),
      ),
    );
  }
}
