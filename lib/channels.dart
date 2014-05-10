part of golib;

Channel nil = new _NilChannel();

class _ChannelClosed {}
var channelClosed = new _ChannelClosed(); 

class _ChannelOp {
  Channel _channel;
  int _operation;
  
  // Operation types.
  static const int send = 0;
  static const int recv = 1;
  
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
  
  int get numBlockedSends;
  int get numBlockedRecvs;

  bool get isOpen;
  bool get isClosed;
  
  /// Detaches the stream [stream] from this channel.
  void detach(Stream stream);

  /// Returns true if and only if calling [recv] would block.
  bool get recvWillBlock;
  
  /// Returns true if and only if calling [recv] would NOT block.
  bool get recvReady;

  /// Receives the next value from this channel.
  /// 
  /// If [doNotBlock] is true and [recv] needs to block to complete, it fails
  /// and returns false.
  /// If this channel is closed, [recv] returns [channelClosed].
  GoFuture recv([bool doNotBlock = false]);
}

/// Write Only Channel.
abstract class WOChannel<E> {
  /// Returns the number of elements in the queue.
  int get len;
  
  /// Returns the capacity of the queue.
  int get cap;
  
  int get numBlockedSends;
  int get numBlockedRecvs;

  bool get isOpen;
  bool get isClosed;
  
  /// Attaches the stream [stream] to this channel.
  /// 
  /// Note that data received from the stream will be sent on this channel.
  void attach(Stream stream);
  
  /// Detaches the stream [stream] from this channel.
  void detach(Stream stream);

  /// When a channel is closed no more data can be sent on it and any [recv]
  /// will return [channelClosed].
  void close();

  /// Returns true if and only if calling [send] would block.
  bool get sendWillBlock;

  /// Returns true if and only if calling [send] would NOT block.
  bool get sendReady;
  
  /// Sends [newVal] on this channel.
  /// 
  /// If [doNotBlock] is true and [send] needs to block to complete, it fails
  /// and returns false.
  /// Note: if you try to send on a closed channel, [send] throws.
  bool send(E newVal, [bool doNotBlock = false]);
}

/// When a channel is [attach]ed to a stream (with [reportErrors] equal to true)
/// and that stream sends an error, [recv] returns the error wrapped in [StreamError].
class StreamError {
  var error;
  
  StreamError(this.error);
}

/// Channel used for bidirectional communication.
class Channel<E> implements ROChannel<E>, WOChannel<E> {
  int _queueSize;
  Queue<E> _queue;
  Queue<Completer> _sendCompleters;
  Queue<Completer> _recvCompleters;
  Queue<E> _sendValues;
  bool _open;
  Completer _sendFutureCompleter;
  Completer _recvFutureCompleter;
  Map<Stream, StreamSubscription> _streamsMap;
  bool _closeWhenStreamsDone;
  
  static const int infinite = -1;
  
  void clear(int dim) {
    _queue = new Queue();
    _queueSize = dim;
    _sendCompleters = new Queue<Completer>();
    _recvCompleters = new Queue<Completer>();
    _sendValues = new Queue<E>();
    _open = true;
    _sendFutureCompleter = null;
    _recvFutureCompleter = null;
    _streamsMap = null;
    _closeWhenStreamsDone = true;
  }
  
  /// Creates a channel of dimension [dim].
  /// 
  /// [dim] can be [Channel.infinite].
  /// Think of a channel as a queue.
  /// [send] on a channel blocks if and only if the channel is full.
  /// [recv] on a channel blocks if and only if the channel is empty.
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
  
  int get numBlockedSends => _sendCompleters.length;
  int get numBlockedRecvs => _recvCompleters.length;
  
  bool get isOpen => _open;
  bool get isClosed => !_open;
  
  bool get closeWhenStreamsDone => _closeWhenStreamsDone;
  set closeWhenStreamsDone(x) { _closeWhenStreamsDone = x; }
  
  /// Attaches [stream] to the channel.
  /// If [detachOnError] is true, if and when [stream] sends an error, [stream]
  /// is detached from the channel.
  /// If [reportErrors] is false, the errors sent by [stream] are ignored and
  /// not sent on the channel. Errors are wrapped in the object [StreamError]
  /// so that you can spot them.
  void attach(Stream stream, {bool detachOnError: false, bool reportErrors: false}) {
    if (isClosed)
      throw new UsageException("You can't attach streams to closed channels!");
    
    if (_streamsMap == null)
      _streamsMap = new Map<Stream, StreamSubscription>();
    else if (_streamsMap.containsKey(stream))
      return;               // can't attach a stream more than once
    
    StreamSubscription subs = stream.listen((data) {
      // data is sent on the channel only if the operation is non-blocking
      // so data may be lost.
      if (isOpen)
        send(data, true);               // doesn't block
    },
    onError: (error) {
      if (isOpen && reportErrors)
        send(new StreamError(error));
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

  /// When a channel is closed no more data can be sent on it and any [recv]
  /// will return [channelClosed].
  /// When a channel is closed, all streams are detached from it.
  void close() {
    if (!_open)
      throw new UsageException("You can't close a channel which is already closed!");
    
    // Detaches all the streams attached to this channel. 
    detachAll();

    _open = false;

    if (_recvCompleters.isNotEmpty) {
      // Unblock all the recv waiting. 
      assert(_queue.isEmpty);
      assert(_sendCompleters.isEmpty);
      _recvCompleters.forEach((Completer c) { c.complete(channelClosed); });
      _recvCompleters.clear();
    }

    _signalStatusChange();
  }

  /// Returns true if and only if calling [send] would block.
  bool get sendWillBlock => _open && _queue.length == _queueSize && _recvCompleters.isEmpty;

  /// Returns true if and only if calling [recv] would block.
  bool get recvWillBlock => _open && _queue.isEmpty && _sendCompleters.isEmpty;
  
  /// Returns true if and only if calling [send] would NOT block.
  bool get sendReady => !sendWillBlock;
  
  /// Returns true if and only if calling [recv] would NOT block.
  bool get recvReady => !recvWillBlock;

  /// Returns a future which completes when the send becomes non-blocking.
  /// If [sendReady] is true, returns null.
  Future _getSendFuture() {
    if (sendReady)
      return null;
    if (_sendFutureCompleter == null)
      _sendFutureCompleter = new Completer();
    return _sendFutureCompleter.future;
  }
  
  /// Returns a future which completes when [recv] becomes non-blocking.
  /// If [recvReady] is true, returns null.
  Future _getRecvFuture() {
    if (recvReady)
      return null;
    if (_recvFutureCompleter == null)
      _recvFutureCompleter = new Completer();
    return _recvFutureCompleter.future;
  }

  /// If some users called [_getSendFuture()] or [_getRecvFuture()] and if [send] or
  /// [recv] became non-blocking, [_signalStatusChange] signals this fact to the users.
  void _signalStatusChange() {
    if (sendReady && _sendFutureCompleter != null) {
        _sendFutureCompleter.complete(0);
        _sendFutureCompleter = null;
    }
    if (recvReady && _recvFutureCompleter != null) {
      _recvFutureCompleter.complete(0);
      _recvFutureCompleter = null;
    }
  }
  
  /// Sends [newVal] on this channel.
  /// 
  /// If [doNotBlock] is true and [send] needs to block to complete, it fails
  /// and returns false.
  /// Note: if you try to send on a closed channel, [send] throws.
  bool send(E newVal, [bool doNotBlock = false]) {
    if (!_open)
      throw new UsageException("You can't send values on a closed channel!");
    
    if (_selectedOpIdx > 0)
      return false;             // don't execute this op (also see goCase)
      
    if (_gatherChOps)
      _singleCaseOps.add(new _ChannelOp(this, _ChannelOp.send));
    else if (_recvCompleters.isNotEmpty) {                 // unblock a recv
      assert(_queue.isEmpty);
      assert(_sendCompleters.isEmpty);
      _recvCompleters.removeFirst().complete(newVal);
    }
    else if (_queue.length != _queueSize) {               // this send is non-blocking
      assert(_sendCompleters.isEmpty);
      _queue.addLast(newVal);
    }
    else {                                                // this send is blocking
      if (doNotBlock)
        return false;
      Completer c = new Completer();
      _sendCompleters.addLast(c);
      _sendValues.addLast(newVal);
      _wait(c.future);
    }
    _signalStatusChange();
    return true;
  }

  /// Receives the next value from this channel.
  /// 
  /// If [doNotBlock] is true and [recv] needs to block to complete, it fails
  /// and returns false.
  /// If this channel is closed, [recv] returns [channelClosed].
  GoFuture<E> recv([bool doNotBlock = false]) {
    GoFuture<E> mf;
    
    if (_selectedOpIdx > 0)
      return null;              // don't execute this op (also see goCase)

    if (_gatherChOps) {
      _singleCaseOps.add(new _ChannelOp(this, _ChannelOp.recv));
      return null;
    }
    
    if (_queue.isNotEmpty) {                   // this recv is non-blocking
      mf = new GoFuture(null);
      mf._setValue(_queue.removeFirst());

      // If _sendCompleters is not empty, the _queue was full but now it has a free slot
      // so we must unblock a send and insert the associated value into the _queue.
      if (_sendCompleters.isNotEmpty) {
        assert(_queue.length == _queueSize - 1);    // the queue was full
        _sendCompleters.removeFirst().complete(0);  // unblock a send
        _queue.addLast(_sendValues.removeFirst());  // insert the value in the _queue
      }
    }
    else if (_sendCompleters.isNotEmpty) {        // unblock a send
      assert(_recvCompleters.isEmpty);
      _sendCompleters.removeFirst().complete(0);
      mf = new GoFuture(null);
      mf._setValue(_sendValues.removeFirst());
    }
    else if (!_open) {                        // channel closed: it doesn't block
      mf = new GoFuture(null);
      mf._setValue(channelClosed);
    }
    else {                                        // this recv is blocking
      if (doNotBlock)
        return null;
      Completer c = new Completer();
      _recvCompleters.addLast(c);
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
  
  int get numBlockedSends => -1;        // not available
  int get numBlockedRecvs => -1;        // not available
  
  bool get isOpen => true;
  bool get isClosed => false;
  
  /// When a channel is closed no more data can be sent on it and any [recv]
  /// will return [channelClosed].
  void close() { }            // has no effect

  /// Returns true if and only if calling [send] would block.
  bool get sendWillBlock => true;

  /// Returns true if and only if calling [recv] would block.
  bool get recvWillBlock => true;
  
  /// Returns true if and only if calling [send] would NOT block.
  bool get sendReady => false;
  
  /// Returns true if and only if calling [recv] would NOT block.
  bool get recvReady => false;

  /// Returns a future which completes when [send] becomes non-blocking.
  Future _getSendFuture() => _c.future;
  
  /// Returns a future which completes when [recv] becomes non-blocking.
  Future _getRecvFuture() => _c.future;

  /// Tries to send [newVal] on this channel and blocks forever, unless
  /// [doNotBlock] is true, in which case returns false.
  bool send(newVal, [bool doNotBlock = false]) {
    if (_selectedOpIdx > 0)
      return false;             // don't execute this op (also see goCase)
      
    if (_gatherChOps)
      _singleCaseOps.add(new _ChannelOp(this, _ChannelOp.send));

    if (doNotBlock)
      return false;
    _wait(_c.future);
    return true;
  }

  /// Tries to receive the next value from this channel and blocks forever, unless
  /// [doNotBlock] is true, in which case returns null.
  GoFuture recv([bool doNotBlock = false]) {
    if (_selectedOpIdx > 0)
      return null;              // don't execute this op (also see goCase)

    if (_gatherChOps) {
      _singleCaseOps.add(new _ChannelOp(this, _ChannelOp.recv));
      return null;
    }
    
    if (doNotBlock)
      return null;
    _wait(_c.future);
    return new GoFuture(_c.future);
  }
}
