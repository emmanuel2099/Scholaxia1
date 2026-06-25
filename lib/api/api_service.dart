import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_endpoints.dart';

// ── Errors ────────────────────────────────────────────────────────────────────

class ApiException implements Exception {
  final int statusCode;
  final String message;

  const ApiException(this.statusCode, this.message);

  @override
  String toString() => message;
}

// ── API client ──────────────────────────────────────────────────────────────

class ApiService {
  ApiService._();
  static final ApiService _instance = ApiService._();
  factory ApiService() => _instance;

  static const _kAccessToken = 'access_token';
  static const _kRefreshToken = 'refresh_token';
  static const _kUserRole = 'user_role';
  static const _kUserId = 'user_id';
  static const _kSetupComplete = 'setup_complete';
  static const _kOnboardingSeen = 'onboarding_seen';
  static const _studentMe = '/api/v1/students/me';

  // ── Token storage ─────────────────────────────────────────────────────────

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kAccessToken);
  }

  Future<String?> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kUserRole);
  }

  Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kUserId);
  }

  Future<void> clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccessToken);
    await prefs.remove(_kRefreshToken);
    await prefs.remove(_kUserRole);
    await prefs.remove(_kUserId);
    await prefs.remove(_kSetupComplete);
  }

  Future<bool> hasSeenOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kOnboardingSeen) ?? false;
  }

  Future<void> markOnboardingSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboardingSeen, true);
  }

  Future<void> _saveRole(String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUserRole, role.toLowerCase().trim());
  }

  Future<void> _saveAuth(AuthResponse auth) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccessToken, auth.accessToken);
    await prefs.setString(_kRefreshToken, auth.refreshToken);
    await prefs.setString(_kUserRole, auth.role.toLowerCase().trim());
    if (auth.userId != null && auth.userId!.isNotEmpty) {
      await prefs.setString(_kUserId, auth.userId!);
    }
    await markOnboardingSeen();
  }

  /// Resolve role from storage or API (fixes teachers sent to exam setup).
  Future<String?> resolveSessionRole() async {
    var role = (await getRole())?.toLowerCase().trim();
    if (role == 'teacher' || role == 'student' || role == 'kind') {
      return role;
    }

    try {
      await getTeacherMe();
      await _saveRole('teacher');
      return 'teacher';
    } catch (_) {}

    try {
      await getStudentProfile();
      await _saveRole('student');
      return 'student';
    } catch (_) {}

    return role;
  }

  Future<bool> hasValidSession() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  // ── HTTP helpers ────────────────────────────────────────────────────────────

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = ApiEndpoints.baseUrl;
    final full = path.startsWith('http')
        ? path
        : (path.startsWith('/') ? '$base$path' : '$base/$path');
    final uri = Uri.parse(full);
    if (query == null || query.isEmpty) return uri;
    return uri.replace(queryParameters: query);
  }

  String resolveMediaUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    if (url.startsWith('http')) return url;
    return _uri(url.startsWith('/') ? url : '/$url').toString();
  }

  Map<String, String> _jsonHeaders() => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  Future<Map<String, String>> _authHeaders() async {
    final token = await getToken();
    return {
      ..._jsonHeaders(),
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  dynamic _parse(http.Response res) {
    final status = res.statusCode;
    dynamic body;
    try {
      body = res.body.isEmpty ? null : jsonDecode(res.body);
    } catch (_) {
      body = res.body;
    }

    if (status >= 200 && status < 300) {
      return body;
    }

    String message = 'Request failed ($status)';
    if (body is Map) {
      final detail = body['detail'];
      if (detail is String) {
        message = detail;
      } else if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        message = first is Map
            ? (first['msg'] ?? first['message'] ?? first).toString()
            : first.toString();
      } else if (body['message'] is String) {
        message = body['message'] as String;
      }
    } else if (body is String && body.isNotEmpty) {
      message = body;
    }

    throw ApiException(status, message);
  }

  List<dynamic> _parseList(http.Response res) {
    final data = _parse(res);
    if (data is List) return data;
    return [];
  }

  Map<String, dynamic> _parseMap(http.Response res) {
    final data = _parse(res);
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  // ── Auth ───────────────────────────────────────────────────────────────────

  Future<AuthResponse> login({
    required String email,
    required String password,
  }) async {
    final res = await http.post(
      _uri(ApiEndpoints.login),
      headers: _jsonHeaders(),
      body: jsonEncode({'email': email, 'password': password}),
    );
    final auth =
        AuthResponse.fromJson(Map<String, dynamic>.from(_parse(res) as Map));
    await _saveAuth(auth);
    return auth;
  }

  Future<AuthResponse> studentSignup({
    required String email,
    required String password,
    required String fullName,
  }) async {
    final res = await http.post(
      _uri(ApiEndpoints.studentSignup),
      headers: _jsonHeaders(),
      body: jsonEncode({
        'email': email,
        'password': password,
        'full_name': fullName,
      }),
    );
    final auth =
        AuthResponse.fromJson(Map<String, dynamic>.from(_parse(res) as Map));
    await _saveAuth(auth);
    return auth;
  }

  Future<AuthResponse> kindSignup({
    required String email,
    required String password,
    required String fullName,
    String ageGroup = '6-8',
    String? gradeLevel,
    String? parentEmail,
  }) async {
    final res = await http.post(
      _uri(ApiEndpoints.kindSignup),
      headers: _jsonHeaders(),
      body: jsonEncode({
        'email': email,
        'password': password,
        'full_name': fullName,
        'age_group': ageGroup,
        if (gradeLevel != null && gradeLevel.isNotEmpty)
          'grade_level': gradeLevel,
        if (parentEmail != null && parentEmail.isNotEmpty)
          'parent_email': parentEmail,
      }),
    );
    final auth =
        AuthResponse.fromJson(Map<String, dynamic>.from(_parse(res) as Map));
    await _saveAuth(auth);
    return auth;
  }

  // ── Kind (young learners) ──────────────────────────────────────────────────

  Future<Map<String, dynamic>> getKindMe() async {
    final res = await http.get(
      _uri(ApiEndpoints.kindMe),
      headers: await _authHeaders(),
    );
    return _parseMap(res);
  }

  Future<List<String>> kindSubjects() async {
    final res = await http.get(_uri(ApiEndpoints.kindSubjects));
    final data = _parseMap(res);
    final raw = data['subjects'];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return ['General', 'Math', 'English', 'Science'];
  }

  Future<String> kindSiaChat({
    required String question,
    String subject = 'General',
  }) async {
    final res = await http.post(
      _uri(ApiEndpoints.kindSiaChat),
      headers: await _authHeaders(),
      body: jsonEncode({'question': question, 'subject': subject}),
    );
    return _parseMap(res)['sia_kind']?.toString() ?? 'No reply.';
  }

  Future<String> kindSiaLearn({
    required String topic,
    String subject = 'General',
  }) async {
    final res = await http.post(
      _uri(ApiEndpoints.kindSiaLearn),
      headers: await _authHeaders(),
      body: jsonEncode({'topic': topic, 'subject': subject}),
    );
    return _parseMap(res)['sia_kind']?.toString() ?? 'No lesson.';
  }

  Future<String> kindSiaQuiz({
    required String topic,
    String subject = 'General',
    int numQuestions = 5,
  }) async {
    final res = await http.post(
      _uri(ApiEndpoints.kindSiaQuiz),
      headers: await _authHeaders(),
      body: jsonEncode({
        'topic': topic,
        'subject': subject,
        'num_questions': numQuestions,
      }),
    );
    return _parseMap(res)['sia_kind']?.toString() ?? 'No quiz.';
  }

  // ── Students ───────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> setupExam({
    required String examType,
    required List<String> subjects,
    required String educationLevel,
  }) async {
    final res = await http.post(
      _uri(ApiEndpoints.setupExam),
      headers: await _authHeaders(),
      body: jsonEncode({
        'exam_type': examType,
        'subjects': subjects,
        'education_level': educationLevel,
      }),
    );
    final data = _parseMap(res);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSetupComplete, true);
    return data;
  }

  Future<Map<String, dynamic>> setupStatus() async {
    final res = await http.get(
      _uri(ApiEndpoints.setupStatus),
      headers: await _authHeaders(),
    );
    return _parseMap(res);
  }

  Future<List<String>> listAvailableSubjects() async {
    final res = await http.get(_uri(ApiEndpoints.studentSubjects));
    final data = _parseMap(res);
    final raw = data['subjects'];
    if (raw is List) {
      return raw.map((e) => e.toString()).toList();
    }
    return [];
  }

  Future<bool> isSetupComplete() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getBool(_kSetupComplete);

    try {
      final data = await setupStatus();
      final complete = data['setup_complete'] == true;
      await prefs.setBool(_kSetupComplete, complete);
      return complete;
    } on ApiException catch (e) {
      // Teachers hit /students/setup-status with 403 — not incomplete setup.
      if (e.statusCode == 403) return true;
      return cached ?? false;
    } catch (_) {
      return cached ?? false;
    }
  }

  /// Triggers GET /students/me so the server auto-creates a profile if missing.
  Future<void> ensureStudentProfile() async {
    try {
      final res = await http.get(
        _uri(_studentMe),
        headers: await _authHeaders(),
      );
      _parse(res);
    } catch (_) {}
  }

  Future<StudentProfile> getStudentProfile() async {
    final res = await http.get(
      _uri(_studentMe),
      headers: await _authHeaders(),
    );
    return StudentProfile.fromJson(_parseMap(res));
  }

  Future<StudentProfile> getStudentProfileById(String userId) async {
    final res = await http.get(
      _uri(ApiEndpoints.studentProfile(userId)),
      headers: await _authHeaders(),
    );
    return StudentProfile.fromJson(_parseMap(res));
  }

  Future<Map<String, dynamic>> walletMe() async {
    final res = await http.get(
      _uri(ApiEndpoints.walletMe),
      headers: await _authHeaders(),
    );
    return _parseMap(res);
  }

  // ── Teacher ────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getTeacherMe() async {
    final res = await http.get(
      _uri(ApiEndpoints.teacherMe),
      headers: await _authHeaders(),
    );
    return _parseMap(res);
  }

  Future<Map<String, dynamic>> updateTeacherProfile({
    String? bio,
    List<String>? subjects,
  }) async {
    final body = <String, dynamic>{};
    if (bio != null) body['bio'] = bio;
    if (subjects != null) body['subjects'] = subjects;

    final res = await http.patch(
      _uri(ApiEndpoints.teacherMe),
      headers: await _authHeaders(),
      body: jsonEncode(body),
    );
    return _parseMap(res);
  }

  // ── Sia ──────────────────────────────────────────────────────────────────────

  Future<SiaResponse> siaAsk({
    required String question,
    required String subject,
    String language = 'english',
    String? educationLevel,
    List<Map<String, dynamic>>? conversationHistory,
    String tutorMode = 'smart',
  }) async {
    final res = await http.post(
      _uri(ApiEndpoints.siaAsk),
      headers: await _authHeaders(),
      body: jsonEncode({
        'question': question,
        'subject': subject,
        'language': language,
        if (educationLevel != null) 'education_level': educationLevel,
        if (conversationHistory != null)
          'conversation_history': conversationHistory,
        'tutor_mode': tutorMode,
      }),
    );
    return SiaResponse.fromJson(_parseMap(res));
  }

  // ── Teacher AI ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> teacherAiAsk({
    required String task,
    required String subject,
    required String educationLevel,
    required String details,
  }) async {
    final res = await http.post(
      _uri(ApiEndpoints.teacherAiAsk),
      headers: await _authHeaders(),
      body: jsonEncode({
        'task': task,
        'subject': subject,
        'education_level': educationLevel,
        'details': details,
      }),
    );
    return _parseMap(res);
  }

  // ── CBT ─────────────────────────────────────────────────────────────────────

  Future<CbtSession> cbtStartSession(String examId) async {
    final res = await http.post(
      _uri(ApiEndpoints.cbtStartSession(examId)),
      headers: await _authHeaders(),
    );
    return CbtSession.fromJson(_parseMap(res));
  }

  Future<CbtResult> cbtSubmit({
    required String sessionId,
    required Map<String, String> answers,
    bool isAutoSubmit = false,
  }) async {
    final res = await http.post(
      _uri(ApiEndpoints.cbtSubmitSession),
      headers: await _authHeaders(),
      body: jsonEncode({
        'session_id': sessionId,
        'answers': answers,
        'is_auto_submit': isAutoSubmit,
      }),
    );
    return CbtResult.fromJson(_parseMap(res));
  }

  Future<List<dynamic>> cbtExams({
    String? examType,
    String? subject,
  }) async {
    final query = <String, String>{};
    if (examType != null && examType.isNotEmpty) {
      query['exam_type'] = examType;
    }
    if (subject != null && subject.isNotEmpty) query['subject'] = subject;

    final res = await http.get(
      _uri(ApiEndpoints.cbtExams, query.isEmpty ? null : query),
    );
    return _parseList(res);
  }

  Future<Map<String, dynamic>> cbtExamsForMe() async {
    final res = await http.get(
      _uri(ApiEndpoints.cbtExamsForMe),
      headers: await _authHeaders(),
    );
    return _parseMap(res);
  }

  Future<List<CbtQuestion>> cbtDownloadExam(String examId) async {
    final res = await http.get(
      _uri(ApiEndpoints.cbtExamDownload(examId)),
      headers: await _authHeaders(),
    );
    final data = _parseMap(res);
    final raw = data['questions'];
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((q) => CbtQuestion.fromJson(Map<String, dynamic>.from(q)))
        .toList();
  }

  Future<CbtResult> cbtSessionResult(String sessionId) async {
    final res = await http.get(
      _uri(ApiEndpoints.cbtSessionResult(sessionId)),
      headers: await _authHeaders(),
    );
    return CbtResult.fromJson(_parseMap(res));
  }

  Future<Map<String, dynamic>> cbtSessionReview(String sessionId) async {
    final res = await http.get(
      _uri(ApiEndpoints.cbtSessionReview(sessionId)),
      headers: await _authHeaders(),
    );
    return _parseMap(res);
  }

  Future<List<dynamic>> cbtMySessions() async {
    final res = await http.get(
      _uri(ApiEndpoints.cbtMySessions),
      headers: await _authHeaders(),
    );
    return _parseList(res);
  }

  Future<List<dynamic>> teacherSchoolExams() async {
    final res = await http.get(
      _uri(ApiEndpoints.cbtSchoolExamsMine),
      headers: await _authHeaders(),
    );
    return _parseList(res);
  }

  Future<Map<String, dynamic>> createSchoolExam({
    required String title,
    required String subject,
    required int durationMinutes,
    required DateTime scheduledStart,
    required DateTime scheduledEnd,
    required List<Map<String, dynamic>> questions,
    bool cameraRequired = false,
    bool aiLocked = false,
    bool blockMinimize = false,
  }) async {
    final res = await http.post(
      _uri(ApiEndpoints.cbtSchoolExamsCreate),
      headers: await _authHeaders(),
      body: jsonEncode({
        'title': title,
        'subject': subject,
        'duration_minutes': durationMinutes,
        'scheduled_start': scheduledStart.toUtc().toIso8601String(),
        'scheduled_end': scheduledEnd.toUtc().toIso8601String(),
        'questions': questions,
        'camera_required': cameraRequired,
        'ai_locked': aiLocked,
        'block_minimize': blockMinimize,
      }),
    );
    return _parseMap(res);
  }

  Future<Map<String, dynamic>> schoolExamResults(String examId) async {
    final res = await http.get(
      _uri(ApiEndpoints.cbtSchoolExamResults(examId)),
      headers: await _authHeaders(),
    );
    return _parseMap(res);
  }

  // ── Community ───────────────────────────────────────────────────────────────

  Future<List<dynamic>> communityChannels() async {
    final res = await http.get(
      _uri(ApiEndpoints.communityChannels),
      headers: await _authHeaders(),
    );
    return _parseList(res);
  }

  Future<List<dynamic>> getMessages({
    required String channelId,
    int limit = 100,
    int offset = 0,
  }) async {
    final res = await http.get(
      _uri(ApiEndpoints.communityMessages, {
        'channel_id': channelId,
        'limit': '$limit',
        'offset': '$offset',
      }),
      headers: await _authHeaders(),
    );
    return _parseList(res);
  }

  Future<Map<String, dynamic>> sendMessage({
    required String channelId,
    required String content,
    String? mediaUrl,
    String? mediaType,
  }) async {
    final res = await http.post(
      _uri(ApiEndpoints.communityMessages),
      headers: await _authHeaders(),
      body: jsonEncode({
        'channel_id': channelId,
        'content': content,
        if (mediaUrl != null) 'media_url': mediaUrl,
        if (mediaType != null) 'media_type': mediaType,
      }),
    );
    return _parseMap(res);
  }

  Future<Map<String, dynamic>> joinChannel({required String channelId}) async {
    final res = await http.post(
      _uri(ApiEndpoints.communityJoin),
      headers: await _authHeaders(),
      body: jsonEncode({'channel_id': channelId}),
    );
    return _parseMap(res);
  }

  Future<Map<String, dynamic>> communityUpload(
    List<int> bytes,
    String filename,
  ) async {
    final token = await getToken();
    final request = http.MultipartRequest(
      'POST',
      _uri(ApiEndpoints.communityUpload),
    );
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    return _parseMap(res);
  }

  Future<List<dynamic>> listPosts({
    required String channelId,
    int limit = 30,
    int offset = 0,
  }) async {
    final res = await http.get(
      _uri(ApiEndpoints.communityPosts, {
        'channel_id': channelId,
        'limit': '$limit',
        'offset': '$offset',
      }),
      headers: await _authHeaders(),
    );
    return _parseList(res);
  }

  Future<Map<String, dynamic>> createPost({
    required String channelId,
    required String content,
    bool isAnonymous = false,
    String visibility = 'everyone',
    String? mediaUrl,
    String? mediaType,
    String? cbtExamId,
  }) async {
    final res = await http.post(
      _uri(ApiEndpoints.communityPosts),
      headers: await _authHeaders(),
      body: jsonEncode({
        'channel_id': channelId,
        'content': content,
        'is_anonymous': isAnonymous,
        'visibility': visibility,
        if (mediaUrl != null) 'media_url': mediaUrl,
        if (mediaType != null) 'media_type': mediaType,
        if (cbtExamId != null) 'cbt_exam_id': cbtExamId,
      }),
    );
    return _parseMap(res);
  }

  Future<Map<String, dynamic>> toggleLike(String postId) async {
    final res = await http.post(
      _uri(ApiEndpoints.communityPostLike(postId)),
      headers: await _authHeaders(),
    );
    return _parseMap(res);
  }

  Future<List<dynamic>> getPinnedPosts(String channelId) async {
    final res = await http.get(
      _uri(ApiEndpoints.communityChannelPinned(channelId)),
      headers: await _authHeaders(),
    );
    return _parseList(res);
  }

  Future<List<dynamic>> getPostComments({
    required String postId,
    required String channelId,
    int limit = 200,
    int offset = 0,
  }) async {
    final all = await listAllPostComments(channelId: channelId, limit: limit);
    final prefix = '@post:$postId';
    return all.where((item) {
      if (item is! Map) return false;
      final content = item['content']?.toString() ?? '';
      return content.startsWith('$prefix ') || content == prefix;
    }).toList();
  }

  Future<List<dynamic>> listAllPostComments({
    required String channelId,
    int limit = 300,
    int offset = 0,
  }) async {
    final res = await http.get(
      _uri(ApiEndpoints.communityPostComments, {
        'channel_id': channelId,
        'limit': '$limit',
        'offset': '$offset',
      }),
      headers: await _authHeaders(),
    );
    return _parseList(res);
  }

  Future<Map<String, dynamic>> addPostComment({
    required String postId,
    required String channelId,
    required String content,
    bool isAnonymous = false,
    String visibility = 'everyone',
  }) async {
    final trimmed = content.trim();
    final body = trimmed.isEmpty ? '@post:$postId' : '@post:$postId $trimmed';
    return createPost(
      channelId: channelId,
      content: body,
      isAnonymous: isAnonymous,
      visibility: visibility,
    );
  }

  String parseCommentText(String raw) {
    final match = RegExp(r'^@post:[^\s]+\s*').firstMatch(raw);
    if (match != null) {
      return raw.substring(match.end).trim();
    }
    return raw.trim();
  }

  // ── Live classes ────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> createLiveClass({
    required String subject,
    required String title,
    String? description,
    String? startTime,
    String? endTime,
    int? durationMinutes,
    bool goLiveNow = false,
  }) async {
    final res = await http.post(
      _uri(ApiEndpoints.liveClassCreate),
      headers: await _authHeaders(),
      body: jsonEncode({
        'subject': subject,
        'title': title,
        if (description != null) 'description': description,
        if (startTime != null) 'start_time': startTime,
        if (endTime != null) 'end_time': endTime,
        if (durationMinutes != null) 'duration_minutes': durationMinutes,
        'go_live_now': goLiveNow,
      }),
    );
    return _parseMap(res);
  }

  Future<Map<String, dynamic>> startLiveClass(String classId) async {
    final res = await http.post(
      _uri(ApiEndpoints.liveClassStart(classId)),
      headers: await _authHeaders(),
    );
    return _parseMap(res);
  }

  Future<Map<String, dynamic>> joinLiveClass(String classId) async {
    final res = await http.post(
      _uri(ApiEndpoints.liveClassJoin(classId)),
      headers: await _authHeaders(),
    );
    return _parseMap(res);
  }

  Future<Map<String, dynamic>> getLiveClassToken(String classId) async {
    final res = await http.get(
      _uri(ApiEndpoints.liveClassToken(classId)),
      headers: await _authHeaders(),
    );
    return _parseMap(res);
  }

  Future<List<dynamic>> listLiveClasses({
    String? subject,
    String? status,
    int limit = 50,
    int offset = 0,
  }) async {
    final query = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
    };
    if (subject != null && subject.isNotEmpty) query['subject'] = subject;
    if (status != null && status.isNotEmpty) query['status'] = status;

    final res = await http.get(
      _uri(ApiEndpoints.liveClassList, query),
      headers: await _authHeaders(),
    );
    return _parseList(res);
  }

  Future<Map<String, dynamic>> getLiveClassDetail(String classId) async {
    final res = await http.get(
      _uri(ApiEndpoints.liveClassDetail(classId)),
      headers: await _authHeaders(),
    );
    return _parseMap(res);
  }

  Future<Map<String, dynamic>> endLiveClass(String classId) async {
    final res = await http.post(
      _uri(ApiEndpoints.liveClassEnd(classId)),
      headers: await _authHeaders(),
    );
    return _parseMap(res);
  }

  Future<Map<String, dynamic>> leaveLiveClass(String classId) async {
    final res = await http.post(
      _uri(ApiEndpoints.liveClassLeave(classId)),
      headers: await _authHeaders(),
    );
    return _parseMap(res);
  }

  Future<List<dynamic>> listLiveClassStudents(String classId) async {
    final res = await http.get(
      _uri(ApiEndpoints.liveClassStudents(classId)),
      headers: await _authHeaders(),
    );
    return _parseList(res);
  }

  Future<void> unmuteLiveClassStudent(String classId, String studentId) async {
    final res = await http.post(
      _uri(ApiEndpoints.liveClassUnmute(classId, studentId)),
      headers: await _authHeaders(),
    );
    _parse(res);
  }

  Future<void> muteLiveClassStudent(String classId, String studentId) async {
    final res = await http.post(
      _uri(ApiEndpoints.liveClassMute(classId, studentId)),
      headers: await _authHeaders(),
    );
    _parse(res);
  }

  Future<Map<String, dynamic>> getLiveKitStatus() async {
    final res = await http.get(
      _uri(ApiEndpoints.liveClassLivekitStatus),
      headers: await _authHeaders(),
    );
    return _parseMap(res);
  }

  Future<List<dynamic>> listLiveSessionRequests({
    String? status,
    int limit = 50,
    int offset = 0,
  }) async {
    final role = await getRole();
    final path = role == 'student'
        ? ApiEndpoints.liveClassRequestsMine
        : ApiEndpoints.liveClassRequests;

    final query = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
    };
    if (status != null && status.isNotEmpty) query['status'] = status;

    final res = await http.get(
      _uri(path, query),
      headers: await _authHeaders(),
    );
    return _parseList(res);
  }

  // ── Materials ───────────────────────────────────────────────────────────────

  Future<List<dynamic>> teacherMaterials() async {
    final res = await http.get(
      _uri(ApiEndpoints.materialsMine),
      headers: await _authHeaders(),
    );
    return _parseList(res);
  }

  Future<Map<String, dynamic>> createMaterial({
    required String title,
    required String subject,
    required String fileUrl,
    String materialType = 'pdf',
    String? description,
    bool isFree = true,
    double price = 0,
  }) async {
    final res = await http.post(
      _uri(ApiEndpoints.materialsCreate),
      headers: await _authHeaders(),
      body: jsonEncode({
        'title': title,
        'subject': subject,
        'material_type': materialType,
        'file_url': fileUrl,
        if (description != null) 'description': description,
        'is_free': isFree,
        'price': price,
      }),
    );
    return _parseMap(res);
  }

  // ── Grading ─────────────────────────────────────────────────────────────────

  Future<List<dynamic>> teacherPendingAssignments() async {
    final res = await http.get(
      _uri(ApiEndpoints.communityAssignmentsPending),
      headers: await _authHeaders(),
    );
    return _parseList(res);
  }

  Future<Map<String, dynamic>> postAssignmentResult({
    required String submissionId,
    required String resultText,
    String? resultScore,
    String? resultFeedback,
  }) async {
    final res = await http.post(
      _uri(ApiEndpoints.communityAssignmentResult(submissionId)),
      headers: await _authHeaders(),
      body: jsonEncode({
        'result_text': resultText,
        if (resultScore != null) 'result_score': resultScore,
        if (resultFeedback != null) 'result_feedback': resultFeedback,
      }),
    );
    return _parseMap(res);
  }

  // ── Notifications ───────────────────────────────────────────────────────────

  Future<List<dynamic>> notifications() async {
    final res = await http.get(
      _uri(ApiEndpoints.notifications),
      headers: await _authHeaders(),
    );
    return _parseList(res);
  }

  Future<void> markAllNotificationsRead() async {
    final res = await http.post(
      _uri(ApiEndpoints.notificationsReadAll),
      headers: await _authHeaders(),
    );
    _parse(res);
  }

  Future<int> unreadNotificationCount() async {
    try {
      final items = await notifications();
      return items.where((n) {
        if (n is! Map) return false;
        return n['is_read'] != true;
      }).length;
    } catch (_) {
      return 0;
    }
  }

  Future<int> unreadCommunityCount() async {
    try {
      final items = await notifications();
      return items.where((n) {
        if (n is! Map || n['is_read'] == true) return false;
        final t = (n['type']?.toString() ?? '').toLowerCase();
        return t.contains('announcement') ||
            t.contains('community') ||
            t.contains('mention');
      }).length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> registerDeviceToken({
    required String token,
    required String platform,
  }) async {
    final res = await http.post(
      _uri(ApiEndpoints.notificationsDeviceToken),
      headers: await _authHeaders(),
      body: jsonEncode({'token': token, 'platform': platform}),
    );
    _parse(res);
  }

  // ── Home ────────────────────────────────────────────────────────────────────

  Future<List<dynamic>> getRecommendationsFeed({
    String? subject,
    String? examType,
    int limit = 20,
    int offset = 0,
  }) async {
    final query = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
    };
    if (subject != null && subject.isNotEmpty) query['subject'] = subject;
    if (examType != null && examType.isNotEmpty) query['exam_type'] = examType;

    final res = await http.get(
      _uri(ApiEndpoints.recommendationsFeed, query),
      headers: await _authHeaders(),
    );
    return _parseList(res);
  }

  Future<Map<String, dynamic>> getHomeFeed() async {
    final res = await http.get(
      _uri(ApiEndpoints.homeFeed),
      headers: await _authHeaders(),
    );
    return _parseMap(res);
  }
}

// ── Models ────────────────────────────────────────────────────────────────────

class AuthResponse {
  final String accessToken;
  final String refreshToken;
  final String role;
  final String? userId;

  const AuthResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.role,
    this.userId,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    final user = json['user'];
    return AuthResponse(
      accessToken: json['access_token'] as String? ?? '',
      refreshToken: json['refresh_token'] as String? ?? '',
      role: json['role']?.toString() ??
          (user is Map ? user['role']?.toString() : null) ??
          'student',
      userId: user is Map ? user['id']?.toString() : null,
    );
  }
}

class StudentProfile {
  final String fullName;
  final String email;
  final String? examType;
  final String? educationLevel;
  final List<String> subjects;
  final bool hasActiveSubscription;

  const StudentProfile({
    required this.fullName,
    required this.email,
    this.examType,
    this.educationLevel,
    this.subjects = const [],
    this.hasActiveSubscription = false,
  });

  factory StudentProfile.fromJson(Map<String, dynamic> json) {
    final rawSubjects = json['selected_subjects'];
    return StudentProfile(
      fullName: json['full_name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      examType: json['exam_type'] as String?,
      educationLevel: json['education_level'] as String?,
      subjects: rawSubjects is List
          ? rawSubjects.map((e) => e.toString()).toList()
          : const [],
      hasActiveSubscription: json['has_active_subscription'] == true,
    );
  }
}

class SiaResponse {
  final String sia;
  final String? board;
  final String? student;
  final String? level;

  const SiaResponse({
    required this.sia,
    this.board,
    this.student,
    this.level,
  });

  factory SiaResponse.fromJson(Map<String, dynamic> json) => SiaResponse(
        sia: json['sia'] as String? ?? '',
        board: json['board']?.toString(),
        student: json['student'] as String?,
        level: json['level'] as String?,
      );
}

class CbtSession {
  final String sessionId;
  final String examId;
  final int durationMinutes;
  final int totalQuestions;

  const CbtSession({
    required this.sessionId,
    required this.examId,
    required this.durationMinutes,
    required this.totalQuestions,
  });

  factory CbtSession.fromJson(Map<String, dynamic> json) => CbtSession(
        sessionId: json['session_id']?.toString() ?? '',
        examId: json['exam_id']?.toString() ?? '',
        durationMinutes: (json['duration_minutes'] as num?)?.toInt() ?? 60,
        totalQuestions: (json['total_questions'] as num?)?.toInt() ?? 0,
      );
}

class CbtQuestion {
  final String id;
  final String text;
  final List<String> options;
  final String? topic;
  final String? imageUrl;

  const CbtQuestion({
    required this.id,
    required this.text,
    required this.options,
    this.topic,
    this.imageUrl,
  });

  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;

  factory CbtQuestion.fromJson(Map<String, dynamic> json) {
    final options = <String>[
      json['option_a']?.toString() ?? '',
      json['option_b']?.toString() ?? '',
      json['option_c']?.toString() ?? '',
      json['option_d']?.toString() ?? '',
    ].where((o) => o.isNotEmpty).toList();

    final image = json['image_url']?.toString() ?? json['imageUrl']?.toString();

    return CbtQuestion(
      id: json['id']?.toString() ?? '',
      text: json['question_text'] as String? ?? json['text'] as String? ?? '',
      options: options,
      topic: json['topic']?.toString(),
      imageUrl: image != null && image.isNotEmpty ? image : null,
    );
  }
}

class CbtResult {
  final double score;
  final double percentage;
  final int totalCorrect;
  final int totalWrong;
  final List<String> weakTopics;

  const CbtResult({
    required this.score,
    required this.percentage,
    required this.totalCorrect,
    required this.totalWrong,
    this.weakTopics = const [],
  });

  factory CbtResult.fromJson(Map<String, dynamic> json) => CbtResult(
        score: (json['score'] as num?)?.toDouble() ?? 0,
        percentage: (json['percentage'] as num?)?.toDouble() ?? 0,
        totalCorrect: (json['total_correct'] as num?)?.toInt() ?? 0,
        totalWrong: (json['total_wrong'] as num?)?.toInt() ?? 0,
        weakTopics: json['weak_topics'] is List
            ? (json['weak_topics'] as List).map((e) => e.toString()).toList()
            : const [],
      );
}
