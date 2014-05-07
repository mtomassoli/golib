library test;

import '../lib/golib.dart';
import 'utils.dart';

import 'dart:async';
import 'dart:io';

part 'loops_test.dart';
part 'functions_test.dart';
part 'channels_test.dart';
part 'waitgroup_test.dart';
part 'daisyChain_test.dart';
part 'pingPong_test.dart';
part 'workers_test.dart';
part 'streams_test.dart';

List<String> _failedTests = [];

List<Test> _tests = [];

void registerTest(Test t) { _tests.add(t); }
void registerTests(List<Test> ts) { _tests.addAll(ts); }

class Test {
  String name;
  Function code;
  Object result;              // string or check function
  
  Test(String name, Function code, Object result) {
    this.name = name;
    this.code = code;
    this.result = result;
  }
}

void _printGlobalResult() {
  var line = '===================================';
  if (_failedTests.isEmpty)
    print('$line\nAll tests succeeded!\n$line');
  else {
    print('$line\nSome tests FAILED:');
    for (var name in _failedTests)
      print('  $name');
    print(line);
  }
}

int _curTest = 0;

void runTests() {
  if (_curTest == _tests.length) {
    _printGlobalResult();
    return;
  }
  
  setOnExitCB(() {
    var result;
    var line = '-----------------------------------';

    var r = _tests[_curTest].result;
    bool correct;
    if (r is Function)          // r is a check function
      correct = r(getLogStr());
    else                        // r is the correct result string
      correct = getLogStr() == r;
    if (correct) 
      result = 'succeeded!';
    else {
      result = 'FAILED!';
      _failedTests.add(_tests[_curTest].name);
    }

    print('$line\n${_tests[_curTest].name} $result\n$line');

    _curTest++;
    runTests();          // run the next test
  });
  
  resetLog();

  _tests[_curTest].code();
}

GoFuture longComputation(int milliseconds) {
  return new GoFuture(new Future.delayed(new Duration(milliseconds: milliseconds), () => "ok"));
}

main() {
  registerLoopsTests();
  registerFunctionsTests();
  registerChannelsTests();
  registerWaitGroupsTests();
  registerDaisyChainTests();
  registerPingPongTests();
  registerWorkersTests();
  registerStreamsTests();
  runTests();
}
