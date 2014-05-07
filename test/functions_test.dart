part of test;

void registerFunctionsTests() {
  registerTest(new Test(
      'functionsTest1',
      functionsTest1,
      'First call|1, 2, 5|Second call|retVal = 3, 4, 11|Second call|retVal = 3, '
      '4, 12|Second call|retVal = 3, 4, 13|'
  ));
}

functionsTest1() {
  void go_func1(int x) {
    int i = 1;
    int j = 2;
    goBody([() {
      log('$i, $j, $x');
      return goReturn;                  }, () {     // break not needed: just a test
      log("this won't print");
    }]);
  }

  ReturnValue<String> go_func2(int x) {
    int i = 3;
    int j = 4;
    return goBody([() {
//      return goBreak;                   }, () {     // ERROR!
      return goReturn("$i, $j, $x");    }, () {     // break not needed: just a test
      log("this won't print");
    }]);
  }
  
  {
    go([() {
      log('First call');
      go_func1(5);                      }, () {     // must break
        
      int i = 0;
      ReturnValue ret;
      
      goWhile(() => i++ < 3, [() {
        log('Second call');
        ret = go_func2(10 + i);         }, () {     // must break
        log('retVal = ${ret.value}');
      }]);
    }]);
  }
}
