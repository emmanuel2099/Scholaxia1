/// Scholaxia Intellect League models + local fallback helpers.
class SilProfile {
  final String gamerTag;
  final String country;
  final String state;
  final String schoolName;
  final String academicClass;
  final bool faceVerified;
  final int coins;
  final int xp;
  final int level;
  final int wins;
  final int losses;
  final double winRate;
  final int currentStreak;
  final int bestStreak;
  final int nationalRank;
  final int aiLevel;
  final List<String> badges;
  final bool enrolled;

  const SilProfile({
    required this.gamerTag,
    required this.country,
    required this.state,
    required this.schoolName,
    required this.academicClass,
    required this.faceVerified,
    required this.coins,
    required this.xp,
    required this.level,
    required this.wins,
    required this.losses,
    required this.winRate,
    required this.currentStreak,
    required this.bestStreak,
    required this.nationalRank,
    required this.aiLevel,
    required this.badges,
    required this.enrolled,
  });

  factory SilProfile.fromJson(Map<String, dynamic> json) => SilProfile(
        gamerTag: json['gamer_tag']?.toString() ?? 'Explorer',
        country: json['country']?.toString() ?? 'Nigeria',
        state: json['state']?.toString() ?? '',
        schoolName: json['school_name']?.toString() ?? '',
        academicClass: json['academic_class']?.toString() ?? 'SS1',
        faceVerified: json['face_verified'] == true,
        coins: (json['coins'] as num?)?.toInt() ?? 0,
        xp: (json['xp'] as num?)?.toInt() ?? 0,
        level: (json['level'] as num?)?.toInt() ?? 1,
        wins: (json['wins'] as num?)?.toInt() ?? 0,
        losses: (json['losses'] as num?)?.toInt() ?? 0,
        winRate: (json['win_rate'] as num?)?.toDouble() ?? 0,
        currentStreak: (json['current_streak'] as num?)?.toInt() ?? 0,
        bestStreak: (json['best_streak'] as num?)?.toInt() ?? 0,
        nationalRank: (json['national_rank'] as num?)?.toInt() ?? 0,
        aiLevel: (json['ai_level'] as num?)?.toInt() ?? 1,
        badges: (json['badges'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        enrolled: json['enrolled'] != false,
      );

  SilProfile copyWith({int? coins, int? xp, int? level, int? wins, int? losses}) =>
      SilProfile(
        gamerTag: gamerTag,
        country: country,
        state: state,
        schoolName: schoolName,
        academicClass: academicClass,
        faceVerified: faceVerified,
        coins: coins ?? this.coins,
        xp: xp ?? this.xp,
        level: level ?? this.level,
        wins: wins ?? this.wins,
        losses: losses ?? this.losses,
        winRate: winRate,
        currentStreak: currentStreak,
        bestStreak: bestStreak,
        nationalRank: nationalRank,
        aiLevel: aiLevel,
        badges: badges,
        enrolled: enrolled,
      );
}

class SilQuestion {
  final String id;
  final String text;
  final List<String> options;
  final String? hint;
  final String? subject;
  final int? correctIndex; // only known locally / after finish

  const SilQuestion({
    required this.id,
    required this.text,
    required this.options,
    this.hint,
    this.subject,
    this.correctIndex,
  });

  factory SilQuestion.fromJson(Map<String, dynamic> json) => SilQuestion(
        id: json['id']?.toString() ?? '',
        text: json['text']?.toString() ?? '',
        options: (json['options'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        hint: json['hint']?.toString(),
        subject: json['subject']?.toString(),
        correctIndex: (json['correct_index'] as num?)?.toInt(),
      );
}

class SilMatch {
  final String id;
  final String mode;
  final String status;
  final String subject;
  final int questionCount;
  final int secondsPerQuestion;
  final int entryCoins;
  final bool faceRequired;
  final List<SilQuestion> questions;
  final int myScore;

  const SilMatch({
    required this.id,
    required this.mode,
    required this.status,
    required this.subject,
    required this.questionCount,
    required this.secondsPerQuestion,
    required this.entryCoins,
    required this.faceRequired,
    required this.questions,
    this.myScore = 0,
  });

  factory SilMatch.fromJson(Map<String, dynamic> json) => SilMatch(
        id: json['id']?.toString() ?? '',
        mode: json['mode']?.toString() ?? 'practice',
        status: json['status']?.toString() ?? 'live',
        subject: json['subject']?.toString() ?? 'Quiz',
        questionCount: (json['question_count'] as num?)?.toInt() ?? 0,
        secondsPerQuestion:
            (json['seconds_per_question'] as num?)?.toInt() ?? 20,
        entryCoins: (json['entry_coins'] as num?)?.toInt() ?? 0,
        faceRequired: json['face_required'] == true,
        myScore: (json['my_score'] as num?)?.toInt() ?? 0,
        questions: (json['questions'] as List?)
                ?.whereType<Map>()
                .map((e) => SilQuestion.fromJson(Map<String, dynamic>.from(e)))
                .toList() ??
            const [],
      );
}

class SilLocalBank {
  static final List<SilQuestion> practice = [
    const SilQuestion(
      id: '1',
      text: 'What is the chemical symbol for water?',
      options: ['O₂', 'H₂O', 'CO₂', 'NaCl'],
      hint: 'Two hydrogen atoms and one oxygen.',
      subject: 'Science',
      correctIndex: 1,
    ),
    const SilQuestion(
      id: '2',
      text: 'Which ocean is the largest in the world?',
      options: ['Atlantic', 'Indian', 'Arctic', 'Pacific'],
      hint: 'Covers more than 30% of Earth.',
      subject: 'General Knowledge',
      correctIndex: 3,
    ),
    const SilQuestion(
      id: '3',
      text: 'What planet is known as the Red Planet?',
      options: ['Venus', 'Mars', 'Jupiter', 'Mercury'],
      hint: 'Named for its rusty colour.',
      subject: 'Science',
      correctIndex: 1,
    ),
    const SilQuestion(
      id: '4',
      text: 'Who was the first President of Nigeria?',
      options: ['Obasanjo', 'Nnamdi Azikiwe', 'Awolowo', 'Buhari'],
      hint: 'Also called Zik.',
      subject: 'History',
      correctIndex: 1,
    ),
    const SilQuestion(
      id: '5',
      text: 'In which year did Nigeria gain independence?',
      options: ['1957', '1960', '1963', '1970'],
      hint: 'October 1st.',
      subject: 'History',
      correctIndex: 1,
    ),
    const SilQuestion(
      id: '6',
      text: 'How many players are on a football team on the field?',
      options: ['9', '10', '11', '12'],
      hint: 'Including the goalkeeper.',
      subject: 'Sports',
      correctIndex: 2,
    ),
    const SilQuestion(
      id: '7',
      text: 'What is the capital of Nigeria?',
      options: ['Lagos', 'Abuja', 'Kano', 'Ibadan'],
      hint: 'Federal Capital Territory.',
      subject: 'General Knowledge',
      correctIndex: 1,
    ),
    const SilQuestion(
      id: '8',
      text: 'What gas do plants absorb from the air?',
      options: ['Oxygen', 'Nitrogen', 'Carbon dioxide', 'Hydrogen'],
      hint: 'Used in photosynthesis.',
      subject: 'Science',
      correctIndex: 2,
    ),
    const SilQuestion(
      id: '9',
      text: 'How many continents are there?',
      options: ['5', '6', '7', '8'],
      hint: 'Including Antarctica.',
      subject: 'General Knowledge',
      correctIndex: 2,
    ),
    const SilQuestion(
      id: '10',
      text: 'Who was the first person on the Moon?',
      options: ['Yuri Gagarin', 'Neil Armstrong', 'Buzz Aldrin', 'John Glenn'],
      hint: 'Apollo 11.',
      subject: 'Space',
      correctIndex: 1,
    ),
  ];
}
