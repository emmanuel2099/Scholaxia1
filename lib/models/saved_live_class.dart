class SavedLiveClass {
  final String id;
  final String title;
  final String subject;
  final String teacher;
  final String classId;
  final DateTime savedAt;
  final String filePath;
  final String mediaType;
  final int? durationSeconds;

  const SavedLiveClass({
    required this.id,
    required this.title,
    required this.subject,
    required this.teacher,
    required this.classId,
    required this.savedAt,
    required this.filePath,
    this.mediaType = 'audio',
    this.durationSeconds,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subject': subject,
        'teacher': teacher,
        'class_id': classId,
        'saved_at': savedAt.toIso8601String(),
        'file_path': filePath,
        'media_type': mediaType,
        'duration_seconds': durationSeconds,
      };

  factory SavedLiveClass.fromJson(Map<String, dynamic> json) {
    return SavedLiveClass(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Live class',
      subject: json['subject']?.toString() ?? '',
      teacher: json['teacher']?.toString() ?? '',
      classId: json['class_id']?.toString() ?? '',
      savedAt: DateTime.tryParse(json['saved_at']?.toString() ?? '') ??
          DateTime.now(),
      filePath: json['file_path']?.toString() ?? '',
      mediaType: json['media_type']?.toString() ?? 'audio',
      durationSeconds: json['duration_seconds'] as int?,
    );
  }

  bool get isVideo => mediaType == 'video';
}
