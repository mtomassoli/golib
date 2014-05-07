part of test;

void registerWaitGroupsTests() {
  registerTest(new Test(
      'waitGroupsTest1',
      waitGroupsTest1,
      'go1: Waiting...|go2: Waiting...|go3: done|go4: done|go1: The wait is over!|'
      'go2: The wait is over!|go2: Waiting again...|go5: done|go6: done|go2: The w'
      'ait is over (again)!|'
  ));
}

waitGroupsTest1() {
  WaitGroup wg = new WaitGroup();
  wg.add(2);
  
  go([() {
    log('go1: Waiting...');
    wg.wait();                            }, () {
    log('go1: The wait is over!');
  }]);

  go([() {
    log('go2: Waiting...');
    wg.wait();                            }, () {
    log('go2: The wait is over!');
    
    wg.wait();              // wg's counter is 0 so it shouldn't block!
    wg.add(2);

    go([() {
      var res = longComputation(50);
      goWait(res);                        }, () {
      log('go5: done');
      wg.done();
    }]);

    go([() {
      var res = longComputation(100);
      goWait(res);                        }, () {
      log('go6: done');
      wg.done();
    }]);
    
    log('go2: Waiting again...');
    wg.wait();                            }, () {
    log('go2: The wait is over (again)!');
  }]);

  go([() {
    var res = longComputation(30);
    goWait(res);                          }, () {
    log('go3: done');
    wg.done();
  }]);

  go([() {
    var res = longComputation(200);
    goWait(res);                          }, () {
    log('go4: done');
    wg.done();
  }]);
}
