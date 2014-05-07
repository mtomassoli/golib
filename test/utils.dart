library utils;

StringBuffer _logStrBuf = new StringBuffer();

void resetLog() { _logStrBuf.clear(); }
String getLogStr() => _logStrBuf.toString();

void log(var x) {
  print(x);
  _logStrBuf.write(x.toString() + '|');
}

class FailedException implements Exception {
  final String msg;
  
  const FailedException([this.msg]);
  String toString() => msg == null ? 'FailedException' : msg;
}
