import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';
import 'sil_face_verify_screen.dart';
import 'sil_models.dart';
import 'sil_shell.dart';
import 'sil_widgets.dart';

class SilOnboardingScreen extends StatefulWidget {
  const SilOnboardingScreen({super.key});

  @override
  State<SilOnboardingScreen> createState() => _SilOnboardingScreenState();
}

class _SilOnboardingScreenState extends State<SilOnboardingScreen> {
  final _api = ApiService();
  int _step = 0;
  bool _busy = false;

  String _country = 'Nigeria';
  String? _state;
  final _schoolCtrl = TextEditingController();
  String? _class;
  final _tagCtrl = TextEditingController();
  bool _rules = false;
  bool _faceDone = false;
  String? _faceB64;

  List<String> _states = const [];
  List<String> _classes = const [
    'JSS1', 'JSS2', 'JSS3', 'SS1', 'SS2', 'SS3', '100L', '200L', '300L', '400L'
  ];

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  Future<void> _loadMeta() async {
    try {
      final meta = await _api.silMeta();
      if (!mounted) return;
      setState(() {
        _states =
            (meta['states'] as List?)?.map((e) => e.toString()).toList() ??
                _states;
        _classes =
            (meta['classes'] as List?)?.map((e) => e.toString()).toList() ??
                _classes;
      });
    } catch (_) {
      setState(() {
        _states = const [
          'Lagos', 'Abuja', 'FCT', 'Ogun', 'Oyo', 'Rivers', 'Kano', 'Enugu',
          'Anambra', 'Delta', 'Edo', 'Kaduna', 'Plateau', 'Imo', 'Osun',
        ];
      });
    }
  }

  @override
  void dispose() {
    _schoolCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  Future<void> _captureFace() async {
    final b64 = await SilFaceVerifyScreen.open(
      context,
      title: 'Signup Face Verification',
      subtitle:
          'Capture your selfie for League identity. This face is checked before every match.',
      requireApi: false,
    );
    if (b64 == null || !mounted) return;
    setState(() {
      _faceB64 = b64;
      _faceDone = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Face captured · liveness OK')),
    );
  }

  Future<void> _finish() async {
    if (!_rules || !_faceDone || _state == null || _class == null) return;
    final tag = _tagCtrl.text.trim();
    final school = _schoolCtrl.text.trim();
    if (tag.length < 3 || school.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Enter school name and a gamer tag (3+ chars).')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final data = await _api.silRegister({
        'country': _country,
        'state': _state,
        'school_name': school,
        'academic_class': _class,
        'gamer_tag': tag,
        'face_selfie_b64': _faceB64,
        'accept_rules': true,
      });
      final profile = SilProfile.fromJson(data);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sil_local_profile', jsonEncode(data));
      await prefs.setString(
          'sil_last_face_ok', DateTime.now().toIso8601String());
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => SilShell(profile: profile)),
        (r) => r.isFirst,
      );
    } catch (_) {
      final local = {
        'gamer_tag': tag,
        'country': _country,
        'state': _state,
        'school_name': school,
        'academic_class': _class,
        'face_verified': true,
        'coins': 100,
        'xp': 0,
        'level': 1,
        'wins': 0,
        'losses': 0,
        'win_rate': 0,
        'current_streak': 0,
        'best_streak': 0,
        'national_rank': 0,
        'ai_level': 1,
        'badges': ['New Challenger'],
        'enrolled': true,
      };
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sil_local_profile', jsonEncode(local));
      await prefs.setString(
          'sil_last_face_ok', DateTime.now().toIso8601String());
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => SilShell(
            profile: SilProfile.fromJson(local),
            offline: true,
          ),
        ),
        (r) => r.isFirst,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _next() {
    if (_step == 0 && _state == null) return;
    if (_step == 1 && _schoolCtrl.text.trim().isEmpty) return;
    if (_step == 2 && _class == null) return;
    if (_step == 3 && !_faceDone) return;
    if (_step == 4 && _tagCtrl.text.trim().length < 3) return;
    if (_step >= 5) {
      _finish();
      return;
    }
    setState(() => _step++);
  }

  @override
  Widget build(BuildContext context) {
    final titles = [
      'Select State',
      'Select School',
      'Select Class',
      'Face Verification',
      'Create Gamer Tag',
      'Accept League Rules',
    ];
    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: AppBar(
        backgroundColor: context.bgColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.textColor),
          onPressed: () {
            if (_step == 0) {
              Navigator.pop(context);
            } else {
              setState(() => _step--);
            }
          },
        ),
        title: Text('League Registration',
            style: TextStyle(
                color: context.textColor, fontWeight: FontWeight.w700)),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(
              value: (_step + 1) / 6,
              color: SilColors.purple,
              backgroundColor: SilColors.purpleSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(height: 16),
            Text(
              titles[_step],
              style: TextStyle(
                color: context.textColor,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(child: _stepBody()),
            SilPrimaryButton(
              label: _step == 5 ? 'Enter the League' : 'Continue',
              loading: _busy,
              onPressed: _next,
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepBody() {
    switch (_step) {
      case 0:
        return ListView(
          children: [
            Text('Country: $_country',
                style: TextStyle(color: context.greyColor)),
            const SizedBox(height: 8),
            ..._states.map((s) => RadioListTile<String>(
                  value: s,
                  groupValue: _state,
                  activeColor: SilColors.purple,
                  title: Text(s),
                  onChanged: (v) => setState(() => _state = v),
                )),
          ],
        );
      case 1:
        return TextField(
          controller: _schoolCtrl,
          decoration: InputDecoration(
            labelText: 'School name',
            filled: true,
            fillColor: SilColors.purpleSoft.withOpacity(0.4),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        );
      case 2:
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _classes
              .map((c) => ChoiceChip(
                    label: Text(c),
                    selected: _class == c,
                    selectedColor: SilColors.purpleSoft,
                    onSelected: (_) => setState(() => _class = c),
                  ))
              .toList(),
        );
      case 3:
        return Column(
          children: [
            Container(
              width: double.infinity,
              height: 220,
              decoration: BoxDecoration(
                color: SilColors.purpleSoft,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                _faceDone
                    ? Icons.verified_user_rounded
                    : Icons.face_retouching_natural,
                size: 88,
                color: SilColors.purple,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Open the camera, complete liveness, and capture your selfie. Required for anti-cheat.',
              style: TextStyle(color: context.greyColor, height: 1.4),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _captureFace,
              icon: const Icon(Icons.camera_alt_rounded),
              label: Text(_faceDone ? 'Recapture selfie' : 'Open camera & verify'),
              style: OutlinedButton.styleFrom(
                foregroundColor: SilColors.purple,
                side: const BorderSide(color: SilColors.purple),
              ),
            ),
          ],
        );
      case 4:
        return TextField(
          controller: _tagCtrl,
          maxLength: 24,
          decoration: InputDecoration(
            labelText: 'Gamer Tag',
            hintText: 'e.g. Explorer',
            filled: true,
            fillColor: SilColors.purpleSoft.withOpacity(0.4),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '• Compete only within your academic class\n'
              '• Face verification every time you open League\n'
              '• Camera stays on during live challenges\n'
              '• Leaving the app pauses and requires re-verify\n'
              '• 10% platform fee on bets',
              style: TextStyle(color: context.textColor, height: 1.55),
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              value: _rules,
              activeColor: SilColors.purple,
              onChanged: (v) => setState(() => _rules = v ?? false),
              title: const Text('I accept the League Rules'),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        );
    }
  }
}
