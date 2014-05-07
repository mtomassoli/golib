part of golib;

class WaitGroup {
  int _count;
  Completer _completer;
  
  void _clear() {
    _count = 0;
    _completer = new Completer();
  }
  
  WaitGroup() { _clear(); }
  
  void _checkCount() {
    if (_count < 0)
      throw new UsageException("WaitGroups can't have negative counts!");
  }
  
  void add(int delta) {
    _count += delta;
    _checkCount();
  }
  
  void done() {
    _count--;
    _checkCount();
    if (_count == 0) {
      _completer.complete(0);     // the value is not important
      _clear();                   // "restart" the WaitGroup
    }
  }
  
  void wait() {
    // If _count is 0, wait doesn't block.
    if (_count > 0)
      _wait(_completer.future);
  }
}
