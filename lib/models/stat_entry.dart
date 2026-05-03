class StatEntry {
  final String packageName;
  final String appName;
  final String date; // yyyy-MM-dd
  final int intercepted;
  final int summarised;

  const StatEntry({
    required this.packageName,
    required this.appName,
    required this.date,
    required this.intercepted,
    required this.summarised,
  });
}

class AppStats {
  final String packageName;
  final String appName;
  int intercepted;
  int summarised;

  AppStats({
    required this.packageName,
    required this.appName,
    this.intercepted = 0,
    this.summarised = 0,
  });
}

class DailyTotal {
  final String date;
  final int intercepted;
  final int summarised;
  const DailyTotal({required this.date, required this.intercepted, required this.summarised});
}
