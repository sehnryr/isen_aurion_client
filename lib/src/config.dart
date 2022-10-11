class Config {
  /// 2 weeks before current date
  static DateTime get defaultStart {
    var now = DateTime.now();
    var today = DateTime(now.year, now.month, now.day, 0, 0, 0);
    return today.subtract(Duration(days: 1 * 7 + now.weekday));
  }

  /// 31th of July of school year
  static DateTime get defaultEnd {
    var now = DateTime.now();
    var endSchoolYear = DateTime(now.year, 7, 31, 23, 59, 59);
    bool newSchoolYear = now.isAfter(endSchoolYear);
    var end = DateTime(now.year + (newSchoolYear ? 1 : 0), 7, 31, 23, 59, 59);
    return end.subtract(Duration(days: end.weekday + 1));
  }
}
