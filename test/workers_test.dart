part of test;

void registerWorkersTests() {
  registerTest(new Test(
      'workersTest',
      workersTest,
      'worker 0 received 0|worker 1 received 1|worker 0 received 2|'
      'worker 1 received 3|worker 0 received 4|worker 1 received 5|'
      'worker 0 received 6|worker 1 received 7|worker 0 received 8|'
      'worker 0 done|worker 1 received 9|worker 1 done|All done!|'
  ));
}

populateChan(Channel<int> ch, int numMessages) {
  go([() {
    int i = 0;
    goWhile(() => i < numMessages, [() {
      ch.send(i);
      i++;
    }]);                                              }, () {
    ch.close();
  }]);
}

createWorker(int i, Channel<int> ch, WaitGroup w) {
  go([() {
    goForIn(ch, [() {
      goSleep(1000);                                  }, () {
      log('worker $i received ${$f}');
    }]);                                              }, () {
    log('worker $i done');
    w.done();
  }]);
}

workersTest() {
  go([() {
    const numMessages = 10;
    const numWorkers = 2;
  
    WaitGroup w = new WaitGroup();
    w.add(2);
    
    Channel<int> ch = new Channel<int>();
    
    populateChan(ch, numMessages);
  
    for (int i = 0; i < numWorkers; i++)
      createWorker(i, ch, w);

    w.wait();                                         }, () {
    log('All done!');
  }]);
}
