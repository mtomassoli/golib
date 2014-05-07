part of golib;

Channel nil = new _NilChannel();

class _ChannelClosed {}
var channelClosed = new _ChannelClosed(); 

class _ChannelOp {
  Channel _channel;
  int _operation;
  
  // Operation types.
  static const int push = 0;
  static const int pop = 1;
  
  _ChannelOp(this._channel, this._operation);

  int get hashCode => (37 * 41 + _channel.hashCode) * 17 + _operation;

  bool operator==(other) {
    if (other is! _ChannelOp)
      return false;
    _ChannelOp ch = other;
    return ch._channel == _channel && ch._operation == _operation;
  }
}

/// Read Only Channel.
abstract class ROChannel<E> {
  /// Returns the number of elements in the queue.
  int get len;
  
  /// Returns the capacity of the queue.
  int get cap;
  
  int get numBlockedPushes;
  int get numBlockedPops;

  bool get isOpen;
  bool get isClosed;
  
  /// Detaches the stream [stream] from this channel.
  void detach(Stream stream);

  /// Returns true if and only if calling a [pop] would block.
  bool get popWillBlock;
  
  /// Returns true if and only if calling a [pop] would NOT block.
  bool get popReady;

  /// Pops the next value from this channel.
  /// 
  /// If [doNotBlock] is true and [pop] needs to block to complete, it fails
  /// and returns false.
  /// If this channel is closed, [pop] returns [channelClosed].
  GoFuture pop([bool doNotBlock = false]);
}

/// Write Only Channel.
abstract class WOChannel<E> {
  /// Returns the number of elements in the queue.
  int get len;
  
  /// Returns the capacity of the queue.
  int get cap;
  
  int get numBlockedPushes;
  int get numBlockedPops;

  bool get isOpen;
  bool get isClosed;
  
  /// Attaches the stream [stream] to this channel.
  /// 
  /// Note that data received from the stream will be pushed 
  void attach(Stream stream);
  
  /// Detaches the stream [stream] from this channel.
  void detach(Stream stream);

  /// When a channel is closed no more data can be [push]ed into it and any [pop]
  /// will return [channelClosed].
  void close();

  /// Returns true if and only if calling a [push] would block.
  bool get pushWillBlock;

  /// Returns true if and only if calling a [push] would NOT block.
  bool get pushReady;
  
  /// Pushes [newVal] into this channel.
  /// 
  /// If [doNotBlock] is true and [push] needs to block to complete, it fails
  /// and returns false.
  /// Note: if you try to push into a closed channel, [push] throws.
  bool push(E newVal, [bool doNotBlock = false]);
}

/// When a channel is [attach]ed to a stream (with [reportErrors] equal to true)
/// and that stream sends an error, [pop] returns the error wrapped in [StreamError].
class StreamError {
  var error;
  
  StreamError(this.error);
}

/// Channel used for bidirectional communication.
class Channel<E> implements ROChannel<E>, WOChannel<E> {
  int _queueSize;
  Queue<E> _queue;
  Queue<Completer> _pushCompleters;
  Queue<Completer> _popCompleters;
  Queue<E> _pushValues;
  bool _open;
  Completer _pushFutureCompleter;
  Completer _popFutureCompleter;
  Map<Stream, StreamSubscription> _streamsMap;
  bool _closeWhenStreamsDone;
  
  static const int infinite = -1;
  
  void clear(int dim) {
    _queue = new Queue();
    _queueSize = dim;
    _pushCompleters = new Queue<Completer>();
    _popCompleters = new Queue<Completer>();
    _pushValues = new Queue<E>();
    _open = true;
    _pushFutureCompleter = null;
    _popFutureCompleter = null;
    _streamsMap = null;
    _closeWhenStreamsDone = true;
  }
  
  /// Creates a channel of dimension [dim].
  /// 
  /// [dim] can be [Channel.infinite].
  /// Think of a channel as a queue.
  /// A [push] on a channel blocks if and only if the channel is full.
  /// A [pop] on a channel blocks if and only if the channel is empty.
  Channel([int dim = 0]) {
    clear(dim);
  }
  
  /// Creates a channel and attaches [stream] to it (see [attach] for the other
  /// parameters).
  Channel.attached(Stream stream, {int dim: infinite, bool detachOnError: false,
                   bool reportErrors: false}) {
    clear(dim);
    attach(stream, detachOnError: detachOnError, reportErrors: reportErrors);
  }
  
  /// Creates a channel and attaches all the stream in [streams] to it (see
  /// [attach] for the other parameters).
  Channel.attachedAll(List<Stream> streams, {int dim: infinite,
                      bool detachOnError: false, bool reportErrors: false}) {
    clear(dim);
    attachAll(streams, detachOnError: detachOnError, reportErrors: reportErrors);
  }

  /// Returns the number of elements in the queue.
  int get len => _queue.length;
  
  /// Returns the capacity of the queue.
  int get cap => _queueSize;
  
  int get numBlockedPushes => _pushCompleters.length;
  int get numBlockedPops => _popCompleters.length;
  
  bool get isOpen => _open;
  bool get isClosed => !_open;
  
  bool get closeWhenStreamsDone => _closeWhenStreamsDone;
  set closeWhenStreamsDone(x) { _closeWhenStreamsDone = x; }
  
  /// Attaches [stream] to the channel.
  /// If [detachOnError] is true, if and when [stream] sends an error, [stream]
  /// is detached from the channel.
  /// If [reportErrors] is false, the errors sent by [stream] are ignored and
  /// not pushed onto the channel. Errors are wrapped in the object [StreamError]
  /// so that you can spot them.
  void attach(Stream stream, {bool detachOnError: false, bool reportErrors: false}) {
    if (isClosed)
      throw new UsageException("You can't attach streams to closed channels!");
    
    if (_streamsMap == null)
      _streamsMap = new Map<Stream, StreamSubscription>();
    else if (_streamsMap.containsKey(stream))
      return;               // can't attach a stream more than once
    
    StreamSubscription subs = stream.listen((data) {
      // data is pushed onto the channel only if the operation is non-blocking
      // so data may be lost.
      if (isOpen)
        push(data, true);               // doesn't block
    },
    onError: (error) {
      if (isOpen && reportErrors)
        push(new StreamError(error));
      if (detachOnError) {
        detach(stream);
        if (_closeWhenStreamsDone && _streamsMap.isEmpty) // all streams detached
          close();
      }
    },
    onDone: () {
      detach(stream);
      if (_closeWhenStreamsDone && _streamsMap.isEmpty) // all streams detached
        close();
    });

    _streamsMap[stream] = subs;
  }

  /// Attaches all the streams in [streams] to the channel (see [attach] for the
  /// parameters).
  void attachAll(List<Stream> streams, {bool detachOnError: false,
                 bool reportErrors: false}) {
    for (Stream s in streams)
      attach(s, detachOnError: detachOnError, reportErrors: reportErrors);
  }
  
  /// Detaches the stream [stream] from this channel.
  void detach(Stream stream) {
    if (_streamsMap == null)
      return;
    
    if (_streamsMap.containsKey(stream)) {
      _streamsMap[stream].cancel();           // cancels the subscription
      _streamsMap.remove(stream);
    }
  }
  
  /// Detaches all the streams attached to this channel.
  void detachAll() {
    if (_streamsMap != null) {
      for (var stream in _streamsMap.keys)
        _streamsMap[stream].cancel();         // cancels the subscription
      _streamsMap.clear();
    }
  }

  /// When a channel is closed no more data can be [push]ed onto it and any [pop]
  /// will return [channelClosed].
  /// When a channel is closed, all streams are detached from it.
  void close() {
    if (!_open)
      throw new UsageException("You can't close a channel which is already closed!");
    
    // Detaches all the streams attached to this channel. 
    detachAll();

    _open = false;

    if (_popCompleters.isNotEmpty) {
      // Unblock all the pop waiting. 
      assert(_queue.isEmpty);
      assert(_pushCompleters.isEmpty);
      _popCompleters.forEach((Completer c) { c.complete(channelClosed); });
      _popCompleters.clear();
    }

    _signalStatusChange();
  }

  /// Returns true if and only if calling a [push] would block.
  bool get pushWillBlock => _open && _queue.length == _queueSize && _popCompleters.isEmpty;

  /// Returns true if and only if calling a [pop] would block.
  bool get popWillBlock => _open && _queue.isEmpty && _pushCompleters.isEmpty;
  
  /// Returns true if and only if calling a [push] would NOT block.
  bool get pushReady => !pushWillBlock;
  
  /// Returns true if and only if calling a [pop] would NOT block.
  bool get popReady => !popWillBlock;

  /// Returns a future which completes when the push becomes non-blocking.
  /// If [pushReady] is true, returns null.
  Future _getPushFuture() {
    if (pushReady)
      return null;
    if (_pushFutureCompleter == null)
      _pushFutureCompleter = new Completer();
    return _pushFutureCompleter.future;
  }
  
  /// Returns a future which completes when the pop becomes non-blocking.
  /// If [popReady] is true, returns null.
  Future _getPopFuture() {
    if (popReady)
      return null;
    if (_popFutureCompleter == null)
      _popFutureCompleter = new Completer();
    return _popFutureCompleter.future;
  }

  /// If some users called [_getPushFuture()] or [_getPopFuture()] and if a [push] or
  /// [pop] became non-blocking, [_signalStatusChange] signals this fact to the users.
  void _signalStatusChange() {
    if (pushReady && _pushFutureCompleter != null) {
        _pushFutureCompleter.complete(0);
        _pushFutureCompleter = null;
    }
    if (popReady && _popFutureCompleter != null) {
      _popFutureCompleter.complete(0);
      _popFutureCompleter = null;
    }
  }
  
  /// Pushes [newVal] into this channel.
  /// 
  /// If [doNotBlock] is true and [push] needs to block to complete, it fails
  /// and returns false.
  /// Note: if you try to push into a closed channel, [push] throws.
  bool push(E newVal, [bool doNotBlock = false]) {
    if (!_open)
      throw new UsageException("You can't push values into a closed channel!");
    
    if (_selectedOpIdx > 0)
      return false;             // don't execute this op (also see goCase)
      
    if (_gatherChOps)
      _singleCaseOps.add(new _ChannelOp(this, _ChannelOp.push));
    else if (_popCompleters.isNotEmpty) {                 // unblock a pop
      assert(_queue.isEmpty);
      assert(_pushCompleters.isEmpty);
      _popCompleters.removeFirst().complete(newVal);
    }
    else if (_queue.length != _queueSize) {               // this push is non-blocking
      assert(_pushCompleters.isEmpty);
      _queue.addLast(newVal);
    }
    else {                                                // this push is blocking
      if (doNotBlock)
        return false;
      Completer c = new Completer();
      _pushCompleters.addLast(c);
      _pushValues.addLast(newVal);
      _wait(c.future);
    }
    _signalStatusChange();
    return true;
  }

  /// Pops the next value from this channel.
  /// 
  /// If [doNotBlock] is true and [pop] needs to block to complete, it fails
  /// and returns false.
  /// If this channel is closed, [pop] returns [channelClosed].
  GoFuture<E> pop([bool doNotBlock = false]) {
    GoFuture<E> mf;
    
    if (_selectedOpIdx > 0)
      return null;              // don't execute this op (also see goCase)

    if (_gatherChOps) {
      _singleCaseOps.add(new _ChannelOp(this, _ChannelOp.pop));
      return null;
    }
    
    if (_queue.isNotEmpty) {                   // this pop is non-blocking
      mf = new GoFuture(null);
      mf._setValue(_queue.removeFirst());

      // If _pushCompleters is not empty, the _queue was full but now it has a free slot
      // so we must unblock a push and insert the associated value into the _queue.
      if (_pushCompleters.isNotEmpty) {
        assert(_queue.length == _queueSize - 1);    // the queue was full
        _pushCompleters.removeFirst().complete(0);  // unblock a push
        _queue.addLast(_pushValues.removeFirst());  // insert the value in the _queue
      }
    }
    else if (_pushCompleters.isNotEmpty) {        // unblock a push
      assert(_popCompleters.isEmpty);
      _pushCompleters.removeFirst().complete(0);
      mf = new GoFuture(null);
      mf._setValue(_pushValues.removeFirst());
    }
    else if (!_open) {                        // channel closed: it doesn't block
      mf = new GoFuture(null);
      mf._setValue(channelClosed);
    }
    else {                                        // this pop is blocking
      if (doNotBlock)
        return null;
      Completer c = new Completer();
      _popCompleters.addLast(c);
      mf = new GoFuture(c.future);
      _wait(c.future);
    }
    _signalStatusChange();
    return mf;
  }
}

class _NilChannel extends Channel {
  Completer _c = new Completer();

  /// Returns the number of elements in the queue.
  int get len => 0;
  
  /// Returns the capacity of the queue.
  int get cap => 0;
  
  int get numBlockedPushes => -1;       // not available
  int get numBlockedPops => -1;         // not available
  
  bool get isOpen => true;
  bool get isClosed => false;
  
  /// When a channel is closed no more data can be [push]ed into it and any [pop]
  /// will return [channelClosed].
  void close() { }            // has no effect

  /// Returns true if and only if calling a [push] would block.
  bool get pushWillBlock => true;

  /// Returns true if and only if calling a [pop] would block.
  bool get popWillBlock => true;
  
  /// Returns true if and only if calling a [push] would NOT block.
  bool get pushReady => false;
  
  /// Returns true if and only if calling a [pop] would NOT block.
  bool get popReady => false;

  /// Returns a future which completes when the push becomes non-blocking.
  Future _getPushFuture() => _c.future;
  
  /// Returns a future which completes when the pop becomes non-blocking.
  Future _getPopFuture() => _c.future;

  /// Tries to push [newVal] onto this channel and blocks forever, unless
  /// [doNotBlock] is true, in which case returns false.
  bool push(newVal, [bool doNotBlock = false]) {
    if (_selectedOpIdx > 0)
      return false;             // don't execute this op (also see goCase)
      
    if (_gatherChOps)
      _singleCaseOps.add(new _ChannelOp(this, _ChannelOp.push));

    if (doNotBlock)
      return false;
    _wait(_c.future);
    return true;
  }

  /// Tries to pop the next value from this channel and blocks forever, unless
  /// [doNotBlock] is true, in which case returns null.
  GoFuture pop([bool doNotBlock = false]) {
    if (_selectedOpIdx > 0)
      return null;              // don't execute this op (also see goCase)

    if (_gatherChOps) {
      _singleCaseOps.add(new _ChannelOp(this, _ChannelOp.pop));
      return null;
    }
    
    if (doNotBlock)
      return null;
    _wait(_c.future);
    return new GoFuture(_c.future);
  }
}
