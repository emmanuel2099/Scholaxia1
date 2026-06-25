/// All Scholaxia API endpoints in one place.
class ApiEndpoints {
  ApiEndpoints._();

  static const String baseUrl = 'https://scholaxia1.onrender.com';
  static const String communityBaseUrl = 'https://scholaxia1.onrender.com';
  static const String _v1 = '/api/v1';

  // Auth
  static const String studentSignup = '$_v1/auth/student/signup';
  static const String kindSignup = '$_v1/auth/kind/signup';
  static const String kindMe = '$_v1/kind/me';
  static const String kindSubjects = '$_v1/kind/subjects';
  static const String kindSiaChat = '$_v1/kind/sia/chat';
  static const String kindSiaLearn = '$_v1/kind/sia/learn';
  static const String kindSiaQuiz = '$_v1/kind/sia/quiz';
  static const String login = '$_v1/auth/login';

  // Students
  static const String setupExam = '$_v1/students/setup-exam';
  static const String setupStatus = '$_v1/students/setup-status';
  static const String studentSubjects = '$_v1/students/subjects';

  // Profiles
  static const String profileMe = '$_v1/profiles/me';
  static String studentProfile(String userId) => '$_v1/profiles/student/$userId';
  static String teacherProfile(String userId) => '$_v1/profiles/teacher/$userId';
  static const String teachersList = '$_v1/profiles/teachers';
  static const String teacherMe = '$_v1/teachers/me';

  // Sia AI
  static const String siaAsk = '$_v1/sia/ask';
  static const String siaExplain = '$_v1/sia/explain';
  static const String siaSolve = '$_v1/sia/solve';
  static const String siaEvaluate = '$_v1/sia/evaluate';
  static const String siaGenerateQuestions = '$_v1/sia/generate-questions';
  static const String siaFeedback = '$_v1/sia/feedback';
  static const String siaExplainWrong = '$_v1/sia/explain-wrong';
  static const String siaLesson = '$_v1/sia/lesson';
  static const String siaDebate = '$_v1/sia/debate';
  static const String siaStudyPlan = '$_v1/sia/study-plan';
  static const String siaProcessPdf = '$_v1/sia/process-pdf';
  static const String siaAnalyzeImage = '$_v1/sia/analyze-image';
  static const String siaSaveNote = '$_v1/sia/notes';
  static const String siaNotes = '$_v1/sia/notes';
  static const String siaAbout = '$_v1/sia/about';
  static const String siaLanguages = '$_v1/sia/languages';

  // Teacher AI
  static const String teacherAiAsk = '$_v1/teacher-ai/ask';

  // CBT
  static const String cbtExams = '$_v1/cbt/exams';
  static const String cbtExamsForMe = '$_v1/cbt/exams/for-me';
  static String cbtExam(String examId) => '$_v1/cbt/exams/$examId';
  static String cbtExamDownload(String examId) => '$_v1/cbt/exams/$examId/download';
  static String cbtStartSession(String examId) => '$_v1/cbt/sessions/$examId/start';
  static const String cbtSubmitSession = '$_v1/cbt/sessions/submit';
  static String cbtSessionResult(String sessionId) => '$_v1/cbt/sessions/$sessionId/result';
  static String cbtSessionReview(String sessionId) => '$_v1/cbt/sessions/$sessionId/review';
  static const String cbtMySessions = '$_v1/cbt/my-sessions';
  static const String cbtSchoolExamsMine = '$_v1/cbt/school-exams/mine';
  static const String cbtSchoolExamsCreate = '$_v1/cbt/school-exams';
  static String cbtSchoolExamResults(String examId) => '$_v1/cbt/school-exams/$examId/results';

  // Materials
  static const String materialsMine = '$_v1/materials/mine';
  static const String materialsCreate = '$_v1/materials/';

  // Community
  static const String communityChannels = '$_v1/community/channels';
  static const String communityJoin = '$_v1/community/join';
  static const String communityUpload = '$_v1/community/upload';
  static const String communityMessages = '$_v1/community/messages';
  static const String communityAssignments = '$_v1/community/assignments';
  static const String communityAssignmentsPending = '$_v1/community/assignments/pending';
  static String communityAssignmentResult(String submissionId) =>
      '$_v1/community/assignments/$submissionId/result';
  static const String communityPosts = '$_v1/community/posts';
  static const String communityPostComments = '$_v1/community/post-comments';
  static const String communityAnnouncements = '$_v1/community/announcements';
  static String communityPostLike(String postId) => '$_v1/community/posts/$postId/like';
  static String communityChannelPinned(String channelId) =>
      '$_v1/community/channels/$channelId/pinned';
  static String communityPostPin(String postId) => '$_v1/community/posts/$postId/pin';

  // Home
  static const String homeFeed = '$_v1/home/feed';
  static const String recommendationsFeed = '$_v1/recommendations/feed';

  // Live classes
  static const String liveClassCreate = '$_v1/live-classes/';
  static const String liveClassList = '$_v1/live-classes/';
  static String liveClassStart(String classId) => '$_v1/live-classes/$classId/start';
  static String liveClassJoin(String classId) => '$_v1/live-classes/$classId/join';
  static String liveClassDetail(String classId) => '$_v1/live-classes/$classId';
  static String liveClassEnd(String classId) => '$_v1/live-classes/$classId/end';
  static String liveClassLeave(String classId) => '$_v1/live-classes/$classId/leave';
  static String liveClassToken(String classId) => '$_v1/live-classes/$classId/token';
  static String liveClassStudents(String classId) => '$_v1/live-classes/$classId/students';
  static String liveClassUnmute(String classId, String studentId) =>
      '$_v1/live-classes/$classId/students/$studentId/unmute';
  static String liveClassMute(String classId, String studentId) =>
      '$_v1/live-classes/$classId/students/$studentId/mute';
  static String liveClassRemove(String classId, String studentId) =>
      '$_v1/live-classes/$classId/students/$studentId/remove';
  static const String liveClassLivekitStatus = '$_v1/live-classes/livekit/status';

  /// WebSocket base (https → wss).
  static String get wsBase {
    final u = Uri.parse(baseUrl);
    final scheme = u.scheme == 'https' ? 'wss' : 'ws';
    final port = u.hasPort ? ':${u.port}' : '';
    return '$scheme://${u.host}$port';
  }

  static String liveClassWs(
    String roomId, {
    required String userId,
    required String role,
  }) {
    final q = Uri(queryParameters: {'user_id': userId, 'role': role});
    return '$wsBase/ws/live-class/${Uri.encodeComponent(roomId)}${q.query.isEmpty ? '' : '?${q.query}'}';
  }
  static const String liveClassHistory = '$_v1/live-classes/history/mine';
  static const String liveClassRequests = '$_v1/live-classes/requests';
  static const String liveClassRequestsMine = '$_v1/live-classes/requests/mine';

  // Library
  static const String libraryStudent = '$_v1/library/student';
  static String libraryRead(String bookId) => '$_v1/library/$bookId/read';

  // Wallet
  static const String walletMe = '$_v1/wallet/me';
  static const String walletWithdraw = '$_v1/wallet/withdraw';

  // Notifications
  static const String notifications = '$_v1/notifications/';
  static const String notificationsReadAll = '$_v1/notifications/read-all';
  static const String notificationsDeviceToken = '$_v1/notifications/device-token';
}
