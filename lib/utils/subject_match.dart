/// Match live-class subject to student selected subjects (mirrors backend subject_matches).
bool subjectMatches(String examSubject, List<String> selectedSubjects) {
  if (selectedSubjects.isEmpty) return false;
  final examS = examSubject.toLowerCase().trim();
  const aliases = {
    'math': 'mathematics',
    'maths': 'mathematics',
    'further math': 'further mathematics',
    'further maths': 'further mathematics',
    'english': 'english language',
    'agric': 'agricultural science',
    'agriculture': 'agricultural science',
    'c.r.s': 'crs',
    'c.r.s.': 'crs',
    'i.r.s': 'irs',
    'i.r.s.': 'irs',
    'econs': 'economics',
    'govt': 'government',
    'geo': 'geography',
  };
  final examNorm = aliases[examS] ?? examS;
  for (final s in selectedSubjects) {
    final sl = s.toLowerCase().trim();
    final slNorm = aliases[sl] ?? sl;
    if (examNorm == slNorm ||
        examS == sl ||
        examS.contains(sl) ||
        sl.contains(examS) ||
        examNorm.contains(slNorm) ||
        slNorm.contains(examNorm)) {
      return true;
    }
  }
  return false;
}
