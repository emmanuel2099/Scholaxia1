import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

class SiaVoiceScreen extends StatefulWidget {
  const SiaVoiceScreen({super.key});

  @override
  State<SiaVoiceScreen> createState() => _SiaVoiceScreenState();
}

class _SiaVoiceScreenState extends State<SiaVoiceScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _waveController;
  late Animation<double> _pulseAnimation;
  bool _isSpeaking = true;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            Expanded(child: _buildVoiceContent()),
            _buildBottomNav(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome, color: AppColors.yellow, size: 16),
              SizedBox(width: 6),
              Text('Scholaxia',
                  style: TextStyle(
                      color: AppColors.yellow,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(width: 10),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Quantum Physics',
                    style: TextStyle(
                        color: AppColors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
                SizedBox(width: 4),
                Icon(Icons.keyboard_arrow_down,
                    color: AppColors.grey, size: 16),
              ],
            ),
          ),
          const Spacer(),
          const Icon(Icons.notifications_outlined,
              color: AppColors.white, size: 22),
          const SizedBox(width: 10),
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.surfaceLight,
            child: const Icon(Icons.person,
                color: AppColors.yellow, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceContent() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1500), Color(0xFF0A0A0A), Color(0xFF0D1A0D)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Topic
            const Text('I. Wave-Particle Duality',
                style: TextStyle(
                    color: AppColors.yellow,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Text(
              'Every particle or quantic entity may be described as either a particle or a wave.',
              style: TextStyle(
                  color: AppColors.white, fontSize: 22, height: 1.4),
            ),
            const Spacer(),
            // Sia avatar
            Center(
              child: Column(
                children: [
                  ScaleTransition(
                    scale: _pulseAnimation,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: AppColors.yellow.withOpacity(0.6),
                            width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.yellow.withOpacity(0.2),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: Container(
                          color: const Color(0xFF1A1500),
                          child: const Icon(Icons.smart_toy_outlined,
                              color: AppColors.yellow, size: 56),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Sia is speaking...',
                      style: TextStyle(
                          color: AppColors.greyLight, fontSize: 14)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Waveform
            _buildWaveform(),
            const Spacer(),
            // Mic button
            Center(
              child: Column(
                children: [
                  GestureDetector(
                    onTap: () => setState(() => _isSpeaking = !_isSpeaking),
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(
                        color: AppColors.yellow,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.mic,
                          color: Colors.black, size: 32),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('TAP TO SPEAK',
                      style: TextStyle(
                          color: AppColors.grey,
                          fontSize: 12,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildWaveform() {
    return AnimatedBuilder(
      animation: _waveController,
      builder: (context, _) {
        return SizedBox(
          height: 48,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(32, (i) {
              final t = _waveController.value;
              final height = 8.0 +
                  20.0 *
                      (0.5 +
                          0.5 *
                              _sineWave(i / 32.0 + t * 2,
                                  frequency: 3.0 + (i % 4) * 0.5));
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                width: 3,
                height: height,
                decoration: BoxDecoration(
                  color: AppColors.yellow.withOpacity(0.7 + 0.3 * (i % 2)),
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  double _sineWave(double x, {double frequency = 1.0}) {
    return (1 + (x * frequency * 3.14159 * 2).abs() % 2 - 1).abs();
  }

  Widget _buildBottomNav() {
    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: AppColors.cardBg,
        border: Border(top: BorderSide(color: Color(0xFF2A2A2A))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavItem(icon: Icons.home_outlined, label: 'Home', isActive: false),
          _NavItem(
              icon: Icons.smart_toy_outlined,
              label: 'Sia',
              isActive: true),
          _NavItem(icon: Icons.quiz_outlined, label: 'CBT', isActive: false),
          _NavItem(
              icon: Icons.cast_for_education_outlined,
              label: 'Classes',
              isActive: false),
          _NavItem(
              icon: Icons.people_outline,
              label: 'Community',
              isActive: false),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  const _NavItem(
      {required this.icon, required this.label, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.yellow.withOpacity(0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon,
              color: isActive ? AppColors.yellow : AppColors.grey,
              size: 22),
        ),
        Text(label,
            style: TextStyle(
                color: isActive ? AppColors.yellow : AppColors.grey,
                fontSize: 10)),
      ],
    );
  }
}
