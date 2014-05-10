part of golib;

void _wait(Future f) {
  if (!_insideGo)
    throw new UsageException(
        "A function you called tried to block outside of a goroutine!");
  _toComplete.add(f);
}

void _waitAll(List<Future> fs) {
  if (!_insideGo)
    throw new UsageException(
        "A function you called tried to block outside of a goroutine!");
  _toComplete.addAll(fs);
}

/// Returns a [Future] that completes if and only if at least one of the futures
/// in [fs] completes.
Future _orFutures(List<Future> fs) {
  // This is a little optimization. Since the future of the channel nil never
  // completes, we ignore it. We must also make sure that there are other
  // futures, though.
  var new_fs = fs.where((f) => f != nil._getRecvFuture()).toList();
  if (new_fs.isNotEmpty)
    fs = new_fs;
  
  bool completed = false;
  Completer c = new Completer();
  
  void func(_) {
    if (!completed)
      c.complete(0);            // the value is not important
    completed = true;
  }
  
  // Each future in fs, when completed, will call func and complete c.future.
  for (var f in fs)
    f.then(func);
  
  return c.future;
}

/// Future used by [golib].
/// 
/// Wrap raw Futures in [GoFuture]s if you want to use them with other golib
/// functions.
class GoFuture<E> {
  Future<E> _f;
  bool _isCompleted = false;
  bool _hasError;
  E _val;
  var _err;
  
  void _checkIsCompleted() {
    if (!_isCompleted)
      throw new UsageException(
          'This GoFuture is not completed. Did you forget to put a code break between '
          'a blocking method (e.g. goWait(fut)) and the code where you access the '
          'content of this GoFuture (e.g. print(fut.value)) ?');
  }
  
  /// Creates a [GoFuture] from a [Future] [f].
  /// 
  /// Note: [f] can be null.
  GoFuture(this._f) {
    if (_f != null)
      _f = _f.then((val) { _setValue(val); })
             .catchError((err) { _setError(err); });
  }
  
  /// If this [GoFuture] completed with a value, returns that value.
  /// 
  /// *Note:* Do not call if this [GoFuture] is not completed.
  E get value { _checkIsCompleted(); return _val; }
  
  /// If the [GoFuture] completed with an error, returns that error.
  /// 
  /// *Note:* Do not call if this [GoFuture] is not completed.
  get error { _checkIsCompleted(); return _err; }
  
  bool get isCompleted => _isCompleted;
  bool get hasError => _hasError;
  
  /// Returns the value or the error this [GoFuture] completed with.
  /// 
  /// *Note:* Do not call if this [GoFuture] is not completed.
  get output { _checkIsCompleted(); return _hasError ? _err : _val; }
  
  void _setValue(var value) {
    _isCompleted = true;
    _hasError = false;
    _val = value;
  }
  
  void _setError(var err) {
    _isCompleted = true;
    _hasError = true;
    _err = err;
  }
  
  /// Returns a [GoFuture] that completes if and only if all the futures in [fs]
  /// complete. 
  static GoFuture and(List<GoFuture> fs) {
    return new GoFuture(Future.wait(fs.map((f) => f._f)));
  }
  
  /// Returns a [GoFuture] that completes if and only if at least one of the
  /// futures in [fs] completes.
  static GoFuture or(List<GoFuture> fs) {
    return new GoFuture(_orFutures(fs.map((f) => f._f)));
  }
  
  /// Returns a [GoFuture] that completes if and only if [this] future and [that]
  /// completes.
  /// 
  /// Note:
  ///   use [GoFuture.and] to combine more than two futures because it's more
  ///   efficient.
  GoFuture operator*(GoFuture that) => GoFuture.and([this, that]);
  
  /// Returns a [GoFuture] that completes if and only if either [this] future or
  /// [that] completes.
  /// 
  /// Note:
  ///   use [GoFuture.or] to combine more than two futures because it's more
  ///   efficient.
  GoFuture operator+(GoFuture that) => GoFuture.or([this, that]);
}

/// Signals to wait for [f] to complete.
/// [f] can be a Future or a GoFuture. A GoFuture is always returned. If [f] is
/// a Future, [goWait] returns a GoFuture which wraps [f], otherwise it returns
/// [f] itself.
/// If [use$] is true and this is the last call to goWait before a break, you
/// can refer to the value the GoFuture completed with as [$].
/// If [f] completed with an error, [$err] is true and [$] contains the error.
/// 
/// Example:
/// 
///     goWait(longComputation());      // long computation returns a GoFuture
///     // <-- break -->
///     print($);
///     
/// Note: [$] is local to each goroutine. Consider the following example:
/// 
///     goWait(...);
///     f();                    // contains a goWait
///     print($);               // refers to the goWait called by f()!
///     
GoFuture goWait(f, [bool use$ = true]) {
  if (!_insideGo)
    throw new UsageException("You can't use goWait outside of a goroutine!");
  
  if (f is Future)
    f = new GoFuture(f);
  else if (f is! GoFuture)
    throw new UsageException('goWait() takes only a Future or a GoFuture!');
  
  if (use$)
    $ = new _ToDeref(f);
  _wait(f._f);
  
  return f;
}

/// Signals to wait for all the [GoFuture]s in [fs] to complete.
void goWaitAll(List<GoFuture> fs) {
  if (!_insideGo)
    throw new UsageException("You can't use goWaitAll outside of a goroutine!");
  
  _waitAll(fs.map((f) => f._f));
}
  
/// Signals to wait for any of the [GoFuture]s in [fs] to complete. 
void goWaitAny(List<GoFuture> fs) {
  if (!_insideGo)
    throw new UsageException("You can't use goWaitAny outside of a goroutine!");
  
  _wait(GoFuture.or(fs)._f);
}

void goSleep(int milliseconds) {
  if (!_insideGo)
    throw new UsageException("You can't use goSleep outside of a goroutine!");

  goWait(new Future.delayed(new Duration(milliseconds: milliseconds)),
         false);        // false = doesn't modify $
}
