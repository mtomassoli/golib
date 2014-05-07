part of golib;

// These globals are used by goSelect.
//
// When _gatherChOps is true, Channel.push and Channel.pop will simply add the
// description of their channel operation to the list _selectOps.
bool _gatherChOps = false;
List<List> _selectOps;
List _singleCaseOps;
int _selectedOpIdx = -1;              // 0-based index of the selected operation
                                      // (-1 means 'disabled')
bool _defaultPresent;
bool _inSelect = false;

void _goWhile(bool cond(), List<Function> blocks, [List<Function> incBlocks = null,
              start$f = null, addData = null]) {
  var allBlocks = [];
  if (incBlocks != null)
    allBlocks.addAll(incBlocks);
  int start = allBlocks.length;             // position of cond
  allBlocks.add(() { if (!cond()) return goBreak; });
  allBlocks.addAll(blocks);
  _cs.addLevel(start, allBlocks, _CodeType._loop, addData, start$f);
}

/// Defines a while loop inside a goroutine.
/// 
/// The [blocks] form the body of the loop.
void goWhile(bool cond(), List<Function> blocks, [List<Function> incBlocks = null]) {
  if (!_insideGo)
    throw new UsageException("You can't use goWhile outside of a goroutine!");

  _goWhile(cond, blocks, incBlocks);
}

/// Defines an infinite loop inside a goroutine.
/// 
/// The code [blocks] form the body of the loop.
void goForever(List<Function> blocks, [List<Function> incBlocks = null]) {
  if (!_insideGo)
    throw new UsageException("You can't use goForever outside of a goroutine!");

  if (incBlocks != null) {
    var allBlocks = new List.from(incBlocks);
    allBlocks.addAll(blocks);
    _cs.addLevel(incBlocks.length, allBlocks, _CodeType._loop);
  }
  else
    _cs.addLevel(0, blocks, _CodeType._loop);
}

/// Defines a for-in loop which reads values from a [source]. [source] can be a
/// channel or a stream. If [source] is a stream, a channel is created and
/// [source] is attached to it. The for-in loop ends when the channel is closed.
/// The element popped from [source] at each cycle is referenced by [$f].
/// Note: if [source] is a stream, a "return goBreak" inside the goForIn closes
///   the channel, otherwise the channel remains open.
/// 
/// Example:
/// 
///     goForIn(ch, [() {
///       print($f);
///     }]);
///     
/// Note: [$f] is local to each goForIn. This means that if two goForIn are nested,
///   each goForIn has its own [$f].
/// 
/// Example:
/// 
///     goForIn(ch1, [() {            // ch1 contains 1, 2, 3, ...
///       goForIn(ch2, [() {
///       }]);                        }, () {
///       print($f);
///     }]);
///     
/// This prints 1, 2, 3, etc...
void goForIn(source, List<Function> blocks) {
  if (!_insideGo)
    throw new UsageException("You can't use goForIn outside of a goroutine!");
  
  bool closeChannelOnBreak = false;
  if (source is Stream) {
    source = new Channel.attached(source);
    closeChannelOnBreak = true;
  }
  else if (source is! ROChannel)
    throw new UsageException("goForIn takes only ROChannels or Streams as source");

  // See go() for an explanation of _ToDeref.
  var _toDeref = new _ToDeref(source.pop());
  var start$f = _toDeref;           // initial value of $f in the goWhile
  // here there is an implicit break (as always, before a goWhile).
  _goWhile(() => $f != channelClosed, blocks,
           [() { $f = _toDeref; _toDeref.goFuture = source.pop(); }], start$f,
           closeChannelOnBreak ? source : null);
}

/// Used in [goSelect].
bool goCase(op1, [op2 = null, op3 = null, op4 = null, op5 = null]) {
  if (!_inSelect)
    throw new UsageException('You can only use goCase in a select!');
  
  Iterable ops = [op1, op2, op3, op4, op5].where((op) => op != null);
  
  if (_gatherChOps) {
    // Add the GoFutures contained in this case branch.
    _singleCaseOps.addAll(ops.where((op) => op is GoFuture));

    // Add the ops gathered from this branch to the global list.
    _selectOps.add(_singleCaseOps);
    
    _singleCaseOps = [];    // makes it ready for the next select branch    
    return false;           // keeps the 'if' branches of the select from being taken
  }

  // Note:
  //  _selectedOpIdx is also used in Channel.push and Channel.pop. It prevents the
  // unselected operation from executing (that is, from doing real work).
  if (_selectedOpIdx == 0) {
    _selectedOpIdx = -1;      // disables it
    return true;              // takes the 'if' branch of the selected operation
  }
  _selectedOpIdx--;
  return false;             // doesn't take the 'if' branch of the current operation
}

/// Used in [goSelect].
bool goDefault() {
  if (!_inSelect)
    throw new UsageException('You can only use goDefault in a select!');

  if (_gatherChOps) {
    _defaultPresent = true;
    return false;           // doesn't take the default branch
  } else {
    _selectedOpIdx = -1;    // disables it
    return true;            // takes the default branch
  }
}

/// Returns true if the operation [op] is non-blocking.
bool _isOpNonBlocking(op) {
  if (op is GoFuture) {             // op is not a channel operation
    if (op.isCompleted)
      return true;
  } 
  else if (op._channel == _ChannelOp.push) {
    if (op._channel.pushReady)
      return true;
  }
  else {          // _ChannelOp.pop
    if (op._channel.popReady)
      return true;
  }
  return false;
}

/// Returns the [future] associated with the operation [op].
/// If [op] is non-blocking, returns null.
Future _getOpFuture(op) {
  if (op is GoFuture)
    return op.isCompleted ? null : op._f;       // completed => non-blocking
  else if (op._operation == _ChannelOp.push)
    return op._channel._getPushFuture();
  else      // _ChannelOp.pop
    return op._channel._getPopFuture();
}

/// Used in the select to specify on operation of pushing onto [channel]
/// without executing the operation. 
pushOnto(Channel channel) {
  if (!_inSelect)
    throw new UsageException('You can only use pushOnto in a select!');
  if (_gatherChOps)
    _singleCaseOps.add(new _ChannelOp(channel, _ChannelOp.push));
  return null;
}

/// Used in the select to specify on operation of popping from [channel]
/// without executing the operation. 
popFrom(Channel channel) {
  if (!_inSelect)
    throw new UsageException('You can only use popFrom in a select!');
  if (_gatherChOps)
    _singleCaseOps.add(new _ChannelOp(channel, _ChannelOp.pop));
  return null;
}

/// Defines a select, which is similar to a switch statement. A select has one
/// or more case labels formed by channel operations or futures. A select chooses
/// a case label whose operations are all non-blocking. If no case label can be
/// chosen, the select blocks until it's possible to choose one case label.
/// 
/// The format is the following:
/// 
///     goSelect(() {
///       var v;
///       if (goCase(v = ch1.pop())) goDo([() {
///         ... 
///       }]);
///       else if (goCase(v = ch1.pop(), future, ch3.push(v))) {
///         ...
///       }
///       else if (goCase(v = ch1.pop(), pushOnto(ch4))) {
///         <some non-blocking computation>
///         ch4.push(123);              // non-blocking
///         ...
///       }
///       else if (goDefault()) {
///         ...
///       }
///     }                     // <---------- remember to put a break here!!!
///     
/// If all the operation of one 'if' are non-blocking, the corresponding branch
/// is taken. The operations of type 'ch.push(x)' or 'x = ch.pop()' are executed,
/// from left to right, just before the corresponding branch is taken.
/// 
/// If you want to make sure that an operation is non-blocking but you want to
/// perform that at a later time, you can use 'pushOnto(ch)' and 'popFrom(ch)'
/// which indicate an operation but don't perform it. You can perform these
/// operations once inside the branch with only one limitation: if you block
/// before performing them, they themself could block.
/// 
/// If you specify a default case, the select never blocks. The default branch
/// is taken if and only if no other branch can be taken.
/// 
/// If more than one branch can be taken, the select chooses one of them randomly.
/// The operation of each case must be distinct. For instance, this is prohibited:
/// 
///     if (goCase(v = ch1.pop(), popFrom(ch1), pushOnto(ch2)) {
///       ...
///     }
///     
void goSelect(Function selectBlock) {
  if (!_insideGo)
    throw new UsageException("You can't use goSelect outside of a goroutine!");

  List<List> selectOps = [];
  bool defaultPresent;

  // The following line of code tells Channel.push and Channel.pop to just
  // populate _selectOps and not perform any push or pop.
  // It also tells goCase to return false so that no branch in the if..else
  // statements is taken in selectBlock.
  _gatherChOps = true;
  _selectOps = [];
  _singleCaseOps = [];
  _defaultPresent = false;
  _inSelect = true;

  selectBlock();                // gather channel operations
  
  _gatherChOps = false;
  _inSelect = false;
  
  // Read _selectOps and _defaultPresent so that other selects can use them.
  selectOps = _selectOps;
  _selectOps = [];
  defaultPresent = _defaultPresent;
  _defaultPresent = false;
  
  // Checks that each group has distinct operations.
  for (var group in selectOps) {
    if (new Set.from(group).length != group.length)
      throw new UsageException(
          'All operations in a single select goCase must be distinct!');
  }
  
  List<int> nonBlockingPos = [];
  int count;          // number of non-blocking operations
  
  bool done = false;

  goWhile(() => !done, [() {
    // Try to select an operation which won't block. If more operations can be
    // selected, choose one randomly.

    // Save the positions (indices) of the non-blocking groups of operations
    // (a group is non-blocking if all the ops in it are non-blocking).
    nonBlockingPos.clear();
    for (int i = 0; i < selectOps.length; ++i) {
      List group = selectOps[i];          // ops of the select branch of index i
      if (group.every((op) => _isOpNonBlocking(op)))      // group is non-blocking
        nonBlockingPos.add(i);
    }
    count = nonBlockingPos.length;

    if (count == 0 && !defaultPresent) {
      // All groups are blocking: we must wait.
      List<Future> fs = [];
      for (List group in selectOps) {
        // Note that not all the op in a group are necessarily blocking, so it
        // waits only for those that are blocking (_getOpFuture() returns null
        // if an op is non-blocking).
        var group_fs = group.map(_getOpFuture).where((f) => f != null);
        fs.add(group_fs.length > 1 ? Future.wait(group_fs) : group_fs.first);
      }
      _wait(_orFutures(fs));      // waits for at least one group to unblock
      return goContinue;
    }                                                 }, () {

    if (count == 0) {       // defaultPresent is true
      // Don't select any operation. The 'if' branch taken will be the default one.
      _selectedOpIdx = selectOps.length;
    } else {
      // Choose the operation to be selected.
      int idx = (count > 1) ? _rng.nextInt(count) : 0;
      _selectedOpIdx = nonBlockingPos[idx];
    }                                                 }, () {
    
    // The code in selectBlock will be executed again but this time goCase will
    // return true in correspondence of the selected channel operation and the
    // associated branch of the if..else will be taken.
    // Also, only the selected operation will be executed.
    _inSelect = true;
    selectBlock();
    _inSelect = false;
    done = true;                  // end of loop!
  }]);
}

/// It's used with if-else constructs to indicate the body.
/// 
/// Example:
/// 
///     if (i < 3) goDo([() {
///       ...
///     }]) else goDo([() {
///       ...
///     }]);
void goDo(List<Function> blocks) {
  if (!_insideGo)
    throw new UsageException("You can't use goDo outside of a goroutine!");

  _cs.addLevel(0, blocks, _CodeType._do);
}

// It's used both as a command and as a real return value.
class ReturnValue<E> {
  E value;
  
  ReturnValue([this.value = null]);
}

/// It's used in functions.
/// 
/// Example:
/// 
///     // void function (goReturn is optional).
///     void go_func1(int x) {
///       int i = 1;
///       int j = 2;
///       goBody([() {
///         ...
///         return goReturn;
///         ...
///       }]);
///     }
///
///     // non-void function (goReturn is mandatory).
///     ReturnValue<String> go_func2(int x) {
///       int i = 3;
///       int j = 4;
///       return goBody([() {
///         ...
///         return goReturn("$i, $j");
///         ...
///       }]);
///     }
///     
///     var ret;
///     go([() {
///       go_func1(1);                        }, () {     // must break!
///       ret = go_func2(2);                  }, () {     // must break!
///       print(res.value);
///     }]);
///     
ReturnValue goBody(List<Function> blocks) {
  ReturnValue rv = new ReturnValue();
  _cs.addLevel(0, blocks, _CodeType._body, rv);
  return rv;
}

ReturnValue goReturn(retVal) => new ReturnValue(retVal);
