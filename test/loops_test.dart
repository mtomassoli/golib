part of test;

void registerLoopsTests() {
  registerTest(new Test(
      'loopsTest1',
      loopsTest1,
      '0|go2: 100|go3: 100|inner loop: 10|go2: 101|go3: 101|inner loop: Error!!!|'
      'go2: 102|go3: 102|1|go2: 103|go3: 103|inner loop: 10|go2: 104|go3: 104|inn'
      'er loop: Error!!!|go2: 105|go2: defer 6|go2: defer 5|go2: defer 4|go2: def'
      'er 3|go2: defer 2|go2: defer 1|go3: 105|go3: defer 6|go3: defer 5|go3: def'
      'er 4|go3: defer 3|go3: defer 2|go3: defer 1|2|inner loop: 10|inner loop: E'
      'rror!!!|go1: defer 4|go1: defer 3|go1: defer 2|go1: defer 1|'
  ));
}

loopsTest1() {
  GoFuture longComputation(i) {
    if (i == 11)
      return new GoFuture(new Future.error('Error!!!'));
    else
      return new GoFuture(new Future.value(i));
  }
  
  {
    int i;
    var res;
  
    go([() {
      i = 0;
      defer([() { log('go1: defer 1'); }]);

      // New goroutines can be launched from anywhere.
      {
        int i;
      
        go([() {
          i = 0;
          goWhile(() => i < 6, [() {
            goWait(longComputation(100 + i));         }, () {
              
            {
              var local_i = i;
              defer([() { log('go3: defer ${local_i + 1}'); }]);
            }
            
            log("go3: ${$}");
            i++;
          }]);
        }]);
      }
      
      goWhile(() => i < 3, [() {
        res = longComputation(i);
        goWait(res);                              }, () {
        log(res.value);
        
        {
          var local_i = i;
          defer([() { log('go1: defer ${local_i + 2}'); }]);
        }
        
        var res2;
        var j = 0;
        goForever([() {
          if (j >= 2)
            return goBreak;
          res2 = longComputation(j + 10);
          goWait(res2);                           }, () {
          if (res2.hasError)
            log('inner loop: ${res2.error}');
          else
            log("inner loop: ${res2.value}");
          j++;
        }]);                                      }, () {
        
        i++;
        
        if (true) goDo([() {        // it's just a test!
          return goContinue;
        }]);                                      }, () {
        
        i++;                        // it shouldn't be executed!
      }]);
    }]);
  }
  
  {
    int i;
    var res;
  
    go([() {
      i = 0;
      goWhile(() => i < 6, [() {
        res = longComputation(100 + i);
        goWait(res);                              }, () {
        log("go2: ${res.value}");

        {
          var local_i = i;
          defer([() { log('go2: defer ${local_i + 1}'); }]);
        }
        
        i++;
      }]);                                        }, () {
      return goExit;                              }, () {
      log("This won't be printed!");
    }]);
  }
}
