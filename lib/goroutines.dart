part of golib;

// Private globals.
List<Future> _toComplete = [];
_ContextStack _cs;
int _numOfActiveGoroutines = 0;
Function _onExitCB = null;
Queue<Function> _deferred = null;
Object _retVal = null;
bool _exitAll = false;          // exits from all goroutines
bool _insideGo = false;

// Used in goForIn() and goWait() and handled in go().
class _ToDeref {
  GoFuture goFuture;
  
  _ToDeref(this.goFuture);
}

class _CodeType {
  static final _CodeType _any = new _CodeType();    // used when it doesn't matter
  static final _CodeType _go = new _CodeType();
  static final _CodeType _loop = new _CodeType();
  static final _CodeType _do = new _CodeType();
  static final _CodeType _body = new _CodeType();   // body of a function
}

class _ContextLevel {
  int _cur;
  List<Function> _blocks;
  _CodeType _codeType;
  Object _addData;              // additional data
  var $f;
  
  _ContextLevel(this._cur, this._blocks, this._codeType, this._addData, this.$f);
}

class _ContextStack {
  int _level = -1;          // initially, there are no levels
  List<_ContextLevel> _cl = [];
  
  int _incLevel = 0;
  
  void clear() {
    _level = -1;
    _cl.clear();
  }
  
  void addLevel(int cur, List<Function> blocks, _CodeType codeType,
                [Object addData = null, start$f = null]) {
    _incLevel++;
    _cl.add(new _ContextLevel(cur, blocks, codeType, addData, start$f));
  }
  
  void removeLevel() {
    _incLevel--;
    _cl.removeLast();
  }
  
  void refreshLevel() {
    _level += _incLevel;
    _incLevel = 0;
  }
  
  int get level => _level;
  
  int get cur => _cl[_level]._cur;
  void set cur(int x) { _cl[_level]._cur = x; }
  void incCur() { _cl[_level]._cur++; }
  
  List<Function> get blocks => _cl[_level]._blocks;

  get codeType => _cl[_level]._codeType;
  set codeType(x) { _cl[_level]._codeType = x; }
  
  get addData => _cl[_level]._addData;
  
  get $f => _cl[_level].$f;
  set $f(x) { _cl[_level].$f = x; }
}

/// Registers a callback to be called on exit.
/// 
/// If [cb] is not null, it will be called when the last goroutine terminates.
void setOnExitCB([Function cb = null]) { _onExitCB = cb; }

/// Can be returned by a code block to break out of the innermost [goWhile] or
/// [goForever].
const goBreak = 1;

/// Can be returned by a code block to go to the beginning of the next cycle in
/// the innermost [goWhile] or [goForever].
const goContinue = 2;

/// Can be returned by a code block to terminate the current goroutine.
const goExit = 3;

/// Creates and executes a goroutine formed by the code [blocks] specified.
/// 
/// Note: go can be called outside or inside other goroutines.
void go(List<Function> blocks) {
  _numOfActiveGoroutines++;
  
  _ContextStack cs = new _ContextStack();
  cs.addLevel(0, blocks, _CodeType._go);

  List<Future> toComplete;
  Queue<Function> deferred = new Queue<Function>();
  var command = null;
  
  var my$, my$err;
  
  recur() {
    while (true) {
      if (_exitAll)
        return;
      
      cs.refreshLevel();              // start from the highest level available
      
      // Handle a command.
      if (command != null) {
        if (command == goExit) {
          // Exits from the entire goroutine doing some cleaning (closes channels
          // used in goForIn).
          while (cs.level >= 0) {
            if (cs.codeType == _CodeType._loop && cs.addData is Channel &&
                cs.addData.isOpen)
              cs.addData.close();         // closes the channel
            cs.removeLevel();
            cs.refreshLevel();
          }
          cs.addLevel(0, [], _CodeType._any);
          cs.refreshLevel();
        }
        else if (command == goBreak || command == goContinue) {
          // Go to the innermost while.
          while (cs.level > 0 && cs.codeType != _CodeType._loop &&
                 cs.codeType != _CodeType._body) {
            // The current level is not related to a loop, so remove it.
            cs.removeLevel();
            cs.refreshLevel();
          }
          if (cs.codeType != _CodeType._loop)
            throw new UsageException(
                'goBreak or goContinue was used outside of a goWhile or goForever!');
          if (command == goBreak) {
            // Quit the goWhile or goForever.
            if (cs.addData is Channel) {
              // The loop is a goForIn (implemented as a goWhile). Closes the
              // channel used in the goForIn.
              if (cs.addData.isOpen)
                cs.addData.close();
            }
            cs.cur = cs.blocks.length;          // goes to the end
            cs.codeType = _CodeType._any;       // non-loop
          }
          else {              // command == goContinue
            // Go to the next iteration.
            cs.cur = 0;
          }
        }
        else if (command == goReturn || command is ReturnValue) {
          // command can be the function goReturn or an instance of ReturnValue.
          // Go to the innermost body (of a function).
          while (cs.level > 0 && cs.codeType != _CodeType._body) {
            // The current level is not related to a body, so remove it, but first
            // does some cleaning (closes channels use in goForIn).
            if (cs.codeType == _CodeType._loop && cs.addData is Channel &&
                cs.addData.isOpen)
              cs.addData.close();         // closes the channel
            cs.removeLevel();
            cs.refreshLevel();
          }
          if (cs.codeType != _CodeType._body)
            throw new UsageException(
                'goReturn was used outside of a function (goBody)!');
          
          // Update the return value.
          cs.addData.value = (command == goReturn) ? null : command.value;
          
          // Quit the function (goBody).
          cs.cur = cs.blocks.length;
        }
        else
          throw new UsageException(
              'A code block can only return goBreak, goContinue, goReturn, '
              'goReturn(retValue) or goExit!');
          
        command = null;
      }

      bool skip = false;
      if (cs.cur == cs.blocks.length) {         // end of iteration
        if (cs.codeType == _CodeType._loop)
          cs.cur = 0;                           // restarts the loop
        else {                      // end of execution
          if (cs.level == 0)
          {
            // If there is deferred code, executes it.
            if (deferred.isNotEmpty) {
              cs.removeLevel();
              cs.addLevel(0, deferred.toList(), _CodeType._any);
              deferred.clear();
              continue;                         // starts executing deferred code
            }
            else {
              _numOfActiveGoroutines--;
              if (_numOfActiveGoroutines == 0 && _onExitCB != null)
                _onExitCB();
              return;                           // this goroutine terminates
            }
          }
          else {
            cs.removeLevel();
            skip = true;
          }
        }
      }
      
      if (!skip) {
        // Signal cs to the other functions that can potentially be called inside
        // the block.
        _cs = cs;
        
        // Some functions, like goForIn and goWait, may assign an instance of
        // _ToDeref to $f and $.
        // _ToDeref contains a GoFuture.
        // Since the assignment happens inside a block in cs.blocks, now the
        // GoFuture in _ToDeref should be completed.
        // We modify $f and $ so that they refer directly to the objects the
        // GoFutures completed with.
        //
        // Note:
        //  - $f is local to each _ContextLevel (see goForIn)
        //  - $ is local to each goroutine (see goWait)
        $f = cs.$f;
        if ($f is _ToDeref) {
          assert($f.goFuture.isCompleted);
          $f = $f.goFuture.value;
        }
        $ = my$;
        $err = my$err;
        if ($ is _ToDeref) {
          assert($.goFuture.isCompleted);
          $err = $.goFuture.hasError;
          $ = $err ? $.goFuture.error : $.goFuture.value;
        }
        
        _deferred = deferred;
        
        // Execute the current block.
        // Note: the block might call some goX functions which add a level to cs,
        //       but that level will be used only after calling cs.refreshLevel
        //       (meaning that the cs.incCur below will still refer to the current
        //       level).
        _insideGo = true;
        command = cs.blocks[cs.cur]();            // execute the current block
        _insideGo = false;
        cs.incCur();
        
        cs.$f = $f;
        $f = null;
        my$ = $;
        $ = null;
        my$err = $err;
        $err = null;
        
        _cs = null;                         // it isn't needed anymore
        
        // Read some flags and reset them immediately (other goroutines may need them).
        toComplete = _toComplete;
        _toComplete = [];
        deferred = _deferred;
        _deferred = null;
        
        if (toComplete.isNotEmpty) {
          Future.wait(toComplete).then((_) {
            toComplete = [];
            recur();
          });
          return;
        }
      }
    }
  }

  // It's better if goroutines don't start to execute immediately. This avoid that
  // recur() reenters if go() is called inside another goroutine.
  // Moreover, if some code creates a series of goroutines, it's better if those
  // begin executing at a later time. This helps with _onExitCB; in fact, if main()
  // creates two goroutines the first one of which terminates immediately, _onExitCB
  // will be called before the second goroutine is even created, which is probably
  // not what the user intended.
  scheduleMicrotask(recur);
}

/// Adds a group of [blocks] of code to the stack of deferred code of the current
/// goroutine (that is, the goroutine which called [defer]).
///
/// The groups of [blocks] associated to a goroutine are called, in LIFO order,
/// immediately before the goroutine terminates.
/// 
/// Note: the code in [blocks] can call [defer].
void defer(List<Function> blocks) {
  if (!_insideGo)
    throw new UsageException("You can't use defer outside of a goroutine!");

  // Adds the blocks of 'blocks' at the beginning of _deferred without altering
  // their order (that is, blocks[1] follows blocks[0], etc...).
  // This way, the groups will be executed in LIFO order.
  for (var b in blocks.reversed)
    _deferred.addFirst(b);
}

void goExitAll() {
  _exitAll = true;
  if (_onExitCB != null)
    _onExitCB();
}
