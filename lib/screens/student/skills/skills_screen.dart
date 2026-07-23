import 'package:flutter/material.dart';
import '../../../api/api_service.dart';
import '../../../services/paystack_checkout_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/student_ui.dart';

class _SkillPhase {
  final String name;
  final String duration;
  final List<String> topics;
  const _SkillPhase(this.name, this.duration, this.topics);
}

class _SkillProgram {
  final String id;
  final String icon;
  final String title;
  final String subtitle;
  final String duration;
  final int fee;
  final String description;
  final List<_SkillPhase> phases;
  final List<String> outcomes;

  const _SkillProgram({
    required this.id,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.duration,
    required this.fee,
    required this.description,
    required this.phases,
    required this.outcomes,
  });
}

const List<_SkillProgram> _kSkillsPrograms = [
  _SkillProgram(
    id: 'web-design',
    icon: '🌐',
    title: 'Web Design',
    subtitle: 'Frontend & Backend',
    duration: '6 months',
    fee: 400000,
    description:
        'Learn to build complete websites and web applications from scratch. The frontend track teaches you how users see and interact with the web — layouts, styling, animations, and modern JavaScript frameworks. The backend track covers servers, databases, APIs, and deployment so you can ship production-ready apps. Graduates can work as junior web developers, freelance site builders, or continue into advanced full-stack roles.',
    phases: [
      _SkillPhase('Frontend Development', '3 months', [
        'HTML5 & semantic markup',
        'CSS3, Flexbox & Grid',
        'JavaScript fundamentals',
        'Responsive design',
        'UI/UX basics',
        'React or Vue introduction',
      ]),
      _SkillPhase('Backend Development', '3 months', [
        'Node.js / Python APIs',
        'Databases (SQL & NoSQL)',
        'Authentication & security',
        'REST APIs',
        'Deployment & hosting',
        'Full-stack portfolio project',
      ]),
    ],
    outcomes: [
      'Build responsive websites and web apps',
      'Create and consume REST APIs',
      'Deploy projects to the internet',
      'Portfolio of 3+ real projects',
    ],
  ),
  _SkillProgram(
    id: 'mobile-app',
    icon: '📱',
    title: 'Mobile App Development',
    subtitle: 'Frontend, Backend & Project',
    duration: '9 months',
    fee: 300000,
    description:
        'Master the full mobile development lifecycle. You will design beautiful interfaces, connect them to real backends, and ship a complete app as your final project. Live classes walk you through industry tools used by startups and agencies worldwide. This program is ideal if you want to build your own app idea or get hired as a mobile developer.',
    phases: [
      _SkillPhase('Mobile Frontend', '3 months', [
        'UI components & navigation',
        'Flutter / React Native basics',
        'State management',
        'Device APIs (camera, GPS)',
        'App store guidelines',
      ]),
      _SkillPhase('Mobile Backend', '3 months', [
        'Firebase / custom APIs',
        'Push notifications',
        'Offline sync',
        'Payment integration',
        'User authentication',
      ]),
      _SkillPhase('Capstone Project', '3 months', [
        'Team or solo app build',
        'Mentor reviews',
        'Testing & debugging',
        'Play Store / App Store prep',
        'Launch & presentation',
      ]),
    ],
    outcomes: [
      'Publish-ready mobile application',
      'Frontend + backend integration skills',
      'App store submission experience',
      'Professional capstone for your CV',
    ],
  ),
  _SkillProgram(
    id: 'gsm-repairs',
    icon: '🔧',
    title: 'Computer / GSM Repairs',
    subtitle: 'Hardware & Software',
    duration: '6 months',
    fee: 150000,
    description:
        'A practical, hands-on program for anyone who wants to earn from device repair. You will work on real phones and computers in live lab sessions — not just theory. Learn hardware fixes (screens, batteries, charging ports) and software solutions (OS issues, unlocking, data recovery). Perfect for opening a repair shop or working in a service center.',
    phases: [
      _SkillPhase('Hardware Repair', '3 months', [
        'Phone & laptop disassembly',
        'Screen & battery replacement',
        'Motherboard basics',
        'Soldering & micro-soldering intro',
        'Diagnostic tools & multimeters',
      ]),
      _SkillPhase('Software & Troubleshooting', '3 months', [
        'OS installation & recovery',
        'Virus removal & optimization',
        'IMEI & firmware flashing',
        'Data recovery basics',
        'Customer service & pricing',
      ]),
    ],
    outcomes: [
      'Diagnose and fix common device faults',
      'Safe disassembly and reassembly',
      'Software troubleshooting toolkit',
      'Business basics for repair shops',
    ],
  ),
  _SkillProgram(
    id: 'graphics',
    icon: '🎨',
    title: 'Graphics Design',
    subtitle: 'Brand, Print & Digital',
    duration: '3 months',
    fee: 70000,
    description:
        'Turn your creativity into a marketable skill. This intensive program covers visual design from concept to finished artwork. Live classes include live demos in industry-standard tools plus critiques of your work. You will build a portfolio of logos, social posts, and print materials that you can show clients on day one after graduation.',
    phases: [
      _SkillPhase('Core Design', '3 months', [
        'Design principles & colour theory',
        'Typography & layout',
        'Adobe Photoshop & Illustrator',
        'Logo & brand identity',
        'Social media creatives',
        'Print design (flyers, banners)',
      ]),
    ],
    outcomes: [
      'Professional design portfolio',
      'Brand identity packages',
      'Social media design templates',
      'Client-ready deliverables',
    ],
  ),
  _SkillProgram(
    id: 'data-analysis',
    icon: '📊',
    title: 'Data Analysis',
    subtitle: 'Excel, SQL & Visualization',
    duration: '6 months',
    fee: 100000,
    description:
        'Data drives every modern business. Learn to collect, clean, analyze, and present data so decision-makers can act on it. Live sessions use real spreadsheets and databases from Nigerian businesses. Whether you want a corporate analyst role or freelance reporting gigs, this program gives you the toolkit employers ask for.',
    phases: [
      _SkillPhase('Foundations', '3 months', [
        'Excel advanced (pivot, VLOOKUP)',
        'Data cleaning & validation',
        'Basic statistics',
        'SQL queries',
        'Introduction to Python for data',
      ]),
      _SkillPhase('Analytics & Reporting', '3 months', [
        'Power BI / Tableau dashboards',
        'Data storytelling',
        'Business KPIs',
        'Real datasets & case studies',
        'Final analytics project',
      ]),
    ],
    outcomes: [
      'Interactive dashboards',
      'SQL & Excel proficiency',
      'Data cleaning workflows',
      'Business report portfolio',
    ],
  ),
  _SkillProgram(
    id: 'cyber-security',
    icon: '🔒',
    title: 'Cyber Security',
    subtitle: 'Defence & Ethical Hacking Basics',
    duration: '3 months',
    fee: 150000,
    description:
        'Protect systems and understand how attackers think — legally and ethically. This fast-track program introduces network security, common attack vectors, and defensive practices used in banks, schools, and tech companies. Live labs simulate real scenarios in a safe environment. A strong entry point into IT security careers or securing your own business.',
    phases: [
      _SkillPhase('Security Fundamentals', '3 months', [
        'Network security basics',
        'Threats & vulnerabilities',
        'Firewalls & encryption',
        'Password & access management',
        'Ethical hacking introduction',
        'Incident response basics',
      ]),
    ],
    outcomes: [
      'Security assessment checklist',
      'Network hardening skills',
      'Ethical hacking lab experience',
      'Foundation for advanced certs',
    ],
  ),
  _SkillProgram(
    id: 'digital-marketing',
    icon: '📢',
    title: 'Digital Marketing',
    subtitle: 'Social, Ads & Growth',
    duration: '2 months',
    fee: 80000,
    description:
        'Learn to grow brands online with proven digital marketing tactics. Short but intensive — perfect for entrepreneurs, influencers, or anyone managing social accounts for businesses. Live classes cover campaign setup, ad targeting, and measuring results in Naira. You will run a practice campaign before graduation.',
    phases: [
      _SkillPhase('Growth Marketing', '2 months', [
        'Social media strategy',
        'Facebook & Instagram ads',
        'Google Ads basics',
        'Content marketing',
        'Email campaigns',
        'Analytics & ROI tracking',
      ]),
    ],
    outcomes: [
      'Complete marketing plan template',
      'Live ad campaign experience',
      'Content calendar system',
      'ROI reporting skills',
    ],
  ),
  _SkillProgram(
    id: 'scratch-robotics',
    icon: '🤖',
    title: 'Scratch Coding & Robotics',
    subtitle: 'Kids, Teens & Beginners',
    duration: '3 months',
    fee: 65000,
    description:
        "An engaging program for young learners and absolute beginners. Start with Scratch's visual blocks to understand programming logic, then move to physical robotics — wiring sensors, motors, and writing code that makes things move. Live classes are interactive and project-based. Great for students, parents who homeschool, or teachers adding STEM to their classroom.",
    phases: [
      _SkillPhase('Coding & Robotics', '3 months', [
        'Scratch block programming',
        'Logic, loops & variables',
        'Arduino / micro:bit basics',
        'Building simple robots',
        'Sensors & motors',
        'STEM project showcase',
      ]),
    ],
    outcomes: [
      'Scratch games & animations',
      'Working robot prototype',
      'STEM problem-solving skills',
      'Showcase project for school or competitions',
    ],
  ),
];

String _formatNaira(int amount) {
  final s = amount.toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return '₦$buf';
}

class SkillsScreen extends StatefulWidget {
  const SkillsScreen({super.key});

  @override
  State<SkillsScreen> createState() => _SkillsScreenState();
}

class _SkillsScreenState extends State<SkillsScreen> {
  String? _expandedId;

  void _toggle(String id) {
    setState(() => _expandedId = _expandedId == id ? null : id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 40),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  const StudentBackButton(),
                  Text(
                    'Skills Training',
                    style: TextStyle(
                      color: context.textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: AppGradients.hero(context),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🚀', style: TextStyle(fontSize: 32)),
                  const SizedBox(height: 8),
                  const Text(
                    'Learn a real, income-earning skill',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Hands-on live classes with expert instructors. Pay in two easy installments.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const StudentSectionTitle(title: 'Programs'),
            ..._kSkillsPrograms.map(_programCard),
          ],
        ),
      ),
    );
  }

  Widget _programCard(_SkillProgram skill) {
    final open = _expandedId == skill.id;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: open ? context.accentColor : context.borderColor,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => _toggle(skill.id),
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: context.accentColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(skill.icon,
                          style: const TextStyle(fontSize: 24)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            skill.title,
                            style: TextStyle(
                              color: context.textColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            skill.subtitle,
                            style: TextStyle(
                                color: context.greyColor, fontSize: 12),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.schedule_rounded,
                                  size: 13, color: context.greyColor),
                              const SizedBox(width: 4),
                              Text(
                                skill.duration,
                                style: TextStyle(
                                    color: context.greyColor, fontSize: 12),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                _formatNaira(skill.fee),
                                style: TextStyle(
                                  color: context.accentColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      open
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: context.greyColor,
                    ),
                  ],
                ),
              ),
            ),
            if (open) _programBody(skill),
          ],
        ),
      ),
    );
  }

  Widget _programBody(_SkillProgram skill) {
    final half = (skill.fee / 2).round();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            skill.description,
            style: TextStyle(
                color: context.textColor, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.accentColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Pay once (full) or half now (${_formatNaira(half)}) + balance (${_formatNaira(skill.fee - half)}) by midpoint — unpaid balance shuts down access. Skill students can join live classes after paying.',
              style: TextStyle(
                color: context.textColor,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Program structure',
            style: TextStyle(
              color: context.textColor,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          ...skill.phases.map((ph) => _phaseTile(ph)),
          const SizedBox(height: 8),
          Text(
            'What you will achieve',
            style: TextStyle(
              color: context.textColor,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          ...skill.outcomes.map(
            (o) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_rounded,
                      color: context.accentColor, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      o,
                      style: TextStyle(
                          color: context.textColor,
                          fontSize: 12.5,
                          height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _openEnroll(skill),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.accentColor,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Enroll now',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _phaseTile(_SkillPhase ph) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  ph.name,
                  style: TextStyle(
                    color: context.textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                ph.duration,
                style: TextStyle(color: context.greyColor, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...ph.topics.map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ',
                      style: TextStyle(color: context.greyColor, fontSize: 12)),
                  Expanded(
                    child: Text(
                      t,
                      style: TextStyle(
                          color: context.greyColor,
                          fontSize: 12,
                          height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openEnroll(_SkillProgram skill) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EnrollSheet(skill: skill),
    );
  }
}

class _EnrollSheet extends StatefulWidget {
  final _SkillProgram skill;
  const _EnrollSheet({required this.skill});

  @override
  State<_EnrollSheet> createState() => _EnrollSheetState();
}

class _EnrollSheetState extends State<_EnrollSheet> {
  final _api = ApiService();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _location = TextEditingController();
  final _start = TextEditingController();
  final _notes = TextEditingController();
  bool _submitting = false;
  String? _error;
  String _paymentMode = 'half'; // once | half

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _location.dispose();
    _start.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    final location = _location.text.trim();
    if (name.isEmpty || phone.isEmpty || location.isEmpty) {
      setState(() => _error = 'Name, phone and location are required.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final paid = await PaystackCheckoutService.purchase(
        context: context,
        api: _api,
        productType: 'skill_enrollment',
        productId: widget.skill.id,
        extra: {
          'full_name': name,
          'phone': phone,
          'email': _email.text.trim(),
          'location': location,
          'preferred_start': _start.text.trim(),
          'notes': _notes.text.trim(),
          'payment_mode': _paymentMode,
          'installment': 1,
        },
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            paid
                ? (_paymentMode == 'once'
                    ? 'Full payment received for ${widget.skill.title}. Live classes unlocked.'
                    : 'Half paid for ${widget.skill.title}. Pay the balance by midpoint or access shuts down. Live classes unlocked meanwhile.')
                : 'Payment was not completed.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final half = (widget.skill.fee / 2).round();
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final payNow = _paymentMode == 'once' ? widget.skill.fee : half;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.borderColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Enroll — ${widget.skill.title}',
                style: TextStyle(
                  color: context.textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Total ${_formatNaira(widget.skill.fee)}. Choose pay once or half now.',
                style: TextStyle(color: context.greyColor, fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              RadioListTile<String>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: 'once',
                groupValue: _paymentMode,
                onChanged: _submitting
                    ? null
                    : (v) => setState(() => _paymentMode = v ?? 'once'),
                title: Text(
                  'Pay once (full) — ${_formatNaira(widget.skill.fee)}',
                  style: TextStyle(
                      color: context.textColor, fontWeight: FontWeight.w700),
                ),
              ),
              RadioListTile<String>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: 'half',
                groupValue: _paymentMode,
                onChanged: _submitting
                    ? null
                    : (v) => setState(() => _paymentMode = v ?? 'half'),
                title: Text(
                  'Pay half now — ${_formatNaira(half)} (balance by midpoint)',
                  style: TextStyle(
                      color: context.textColor, fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  'If balance is not paid by midpoint, enrollment shuts down.',
                  style: TextStyle(color: context.greyColor, fontSize: 11.5),
                ),
              ),
              const SizedBox(height: 8),
              _field(_name, 'Full name *'),
              _field(_phone, 'Phone number *',
                  keyboard: TextInputType.phone),
              _field(_email, 'Email',
                  keyboard: TextInputType.emailAddress),
              _field(_location, 'Location (town / city / state) *'),
              _field(_start, 'Preferred start (optional)'),
              _field(_notes, 'Notes (optional)', maxLines: 3),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: Colors.red.shade400, fontSize: 12.5),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.accentColor,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black),
                        )
                      : Text(
                          'Continue to pay ${_formatNaira(payNow)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String hint,
      {TextInputType? keyboard, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        keyboardType: keyboard,
        maxLines: maxLines,
        style: TextStyle(color: context.textColor, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: context.greyColor, fontSize: 13),
          filled: true,
          fillColor: context.bgColor,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: context.borderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: context.borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: context.accentColor, width: 1.5),
          ),
        ),
      ),
    );
  }
}
