part of golib;

Random _rng = new Random();

/// Exception generated when [golib] is used inappropriately.
class UsageException implements Exception {
  final String msg;

  const UsageException([this.msg]);
  String toString() => msg == null ? 'UsageException' : msg;
}
