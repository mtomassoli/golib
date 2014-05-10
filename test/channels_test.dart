part of test;

void registerChannelsTests() {
  registerTest(new Test(
      'channelsTest1',
      channelsTest1,
      'A1|B1|res = ok|A2|B2|val = 123|'
  ));
  
  registerTest(new Test(
      'channelsTest2',
      channelsTest2,
      'go1: Waiting for long computation...|go2: sending 5 on c...|go1: computa'
      'tion terminated (res = ok)|go1: receiving from c...|go1: value received '
      '(val = 5)|go2: value sent|'
  ));
  
  registerTest(new Test(
      'channelsTest3',
      channelsTest3,
      'A1|B1|B2|A2|A3|B3|'
  ));
  
  registerTest(new Test(
      'channelsTest4',
      channelsTest4,
      'A1|A2|A3|A4|B1: a|B2: b|B3: c|B4: d|A5|A6|B5: e|'
  ));

  registerTest(new Test(
      'channelsTest5',
      channelsTest5,
      "Channel closed.|1|2|Instance of '_ChannelClosed'|"
  ));

  registerTest(new Test(
      'channelsTest6',
      channelsTest6,
      "Channel closed.|Instance of '_ChannelClosed'|Instance of '_ChannelClosed'|"
  ));

  registerTest(new Test(
      'channelsTest7',
      channelsTest7,
      (String s) => s.split('|').length == 7      // includes the empty line
  ));

  registerTest(new Test(
      'channelsTest8',
      channelsTest8,
      'ch1 is now nil|ch2 is now nil|The wait is over!|'
  ));

  registerTest(new Test(
      'channelsTest9',
      channelsTest9,
      'inner loop: 4|inner loop: res = 123|inner loop: 5|outer loop: 1|'
      'outer loop: 2|outer loop: 3|'
  ));
}

channelsTest1() {
  Channel<int> c = new Channel();        // unbuffered channel
  
  {
    GoFuture res;
    
    go([() {
      log('A1');
      res = longComputation(1000);
      goWait(res);                          }, () {
      log('res = ${res.value}');
      c.send(123);                          }, () {
      log('A2');
    }]);
  }
  
  {
    GoFuture val;
    
    go([() {
      log('B1');
      val = c.recv();                       }, () {
      log('B2');
      log('val = ${val.value}');
    }]);
  }
}

channelsTest2() {
  Channel<int> c = new Channel();        // unbuffered channel
  
  {
    GoFuture res, val;
    
    go([() {
      res = longComputation(1000);
      log('go1: Waiting for long computation...');
      goWait(res);                                                  }, () {
      log('go1: computation terminated (res = ${res.value})');
      log('go1: receiving from c...');
      val = c.recv();                                               }, () {
      log('go1: value received (val = ${val.value})');
    }]);
  }
  
  {
    go([() {
      log('go2: sending 5 on c...');
      c.send(5);                                                    }, () {
      log('go2: value sent');
    }]);
  }
}

channelsTest3() {
  Channel<int> c = new Channel();        // unbuffered channel
  
  {
    go([() {
      log('A1');
      c.send(1);
      c.send(2);                      }, () {
      log('A2');
      c.send(3);                      }, () {
      log('A3');
    }]);
  }
  
  {
    GoFuture v1, v2, v3;
    
    go([() {
      log('B1');
      v1 = c.recv();
      v2 = c.recv();                  }, () {
      log('B2');
      v3 = c.recv();                  }, () {
      log('B3');
    }]);
  }
}

channelsTest4() {
  Channel<String> sem = new Channel(3);
  
  {
    go([() {
      log('A1');
      sem.send('a');          }, () {
      log('A2');
      sem.send('b');          }, () {
      log('A3');
      sem.send('c');          }, () {
      log('A4');
      sem.send('d');          }, () {
      log('A5');
      sem.send('e');          }, () {
      log('A6');
    }]);
  }

  {
    GoFuture x;
    
    go([() {
      x = sem.recv();
      log('B1: ${x.value}');
      x = sem.recv();                 }, () {
      log('B2: ${x.value}');
      x = sem.recv();                 }, () {
      log('B3: ${x.value}');
      x = sem.recv();                 }, () {
      log('B4: ${x.value}');
      x = sem.recv();                 }, () {
      log('B5: ${x.value}');
    }]);
  }
}

channelsTest5() {
  Channel<int> ch = new Channel(1);
  
  {
    go([() {
      ch.send(1);                 }, () {
      ch.send(2);                 }, () {
      ch.close();
      log('Channel closed.');
    }]);
  }

  {
    GoFuture val;
    
    go([() {
      var res = longComputation(100);
      goWait(res);
      val = ch.recv();            }, () {
      log('${val.value}');
      val = ch.recv();            }, () {
      log('${val.value}');
      val = ch.recv();            }, () {
      log('${val.value}');
    }]);
  }
}

channelsTest6() {
  Channel<int> ch = new Channel(1);
  
  {
    GoFuture val;
    
    go([() {
      val = ch.recv();              }, () {
      log('${val.value}');
    }]);
  }

  {
    GoFuture val;
    
    go([() {
      val = ch.recv();              }, () {
      log('${val.value}');
    }]);
  }

  {
    go([() {
      var res = longComputation(100);
      goWait(res);                  }, () {
      ch.close();
      log('Channel closed.');
    }]);
  }
}

channelsTest7() {
  Channel<int> ch1 = new Channel();
  Channel<int> ch2 = new Channel();
  Channel<int> ch3 = new Channel();
  Channel<int> ch4 = new Channel();
  Channel<int> ch5 = new Channel();
  GoFuture future;

  void func1(WOChannel ch1, WOChannel c2, WOChannel c3) {
    go([() {
      future = longComputation(1);
      goWait(longComputation(100));       }, () {
      ch1.send(1);
      ch2.send(2);
      ch3.send(3);                        }, () {
      ch1.send(1);
      ch4.send(4);                        }, () {
      ch5.send(5);
    }]);
  }

  void func2(ROChannel ch1, ROChannel ch2, ROChannel ch3, ROChannel ch4,
             ROChannel ch5)
  {
    int numToReceive = 6;
    
    go([() {
      goWhile(() => numToReceive > 0, [() {
        goSelect(() {
          var v, w;
          if (goCase(v = ch2.recv())) { 
            log('ch2: ${v.value}');
            numToReceive--;
          }
          else if (goCase(v = ch1.recv(), future, w = ch3.recv())) {
            log('ch1: ${v.value}');
            log('ch3: ${w.value}');
            numToReceive -= 2;
          }
          else if (goCase(v = ch1.recv(), w = ch4.recv())) {
            log('ch1: ${v.value}');
            log('ch4: ${w.value}');
            numToReceive -= 2;
          }
          else if (goCase(recvFrom(nil)))
            log('Will never happen');
          else if (goCase(recvFrom(ch5))) {
            log('ch5: ${ch5.recv().value}');
            numToReceive--;
          }
        });
      }]);
    }]);
  }
  
  func1(ch1, ch2, ch3);
  func2(ch1, ch2, ch3, ch4, ch5);
}

channelsTest8() {
  Channel<int> ch1 = new Channel<int>();
  Channel<int> ch2 = new Channel<int>();
  
  go([() {
    int i = 0;
    goWhile(() => i++ < 2, [() {
      goSelect(() {
        var x;
        if (goCase(x = ch1.recv())) {
          ch1 = nil;
          log('ch1 is now nil');
        }
        else if (goCase(x = ch2.recv())) {
          ch2 = nil;
          log('ch2 is now nil');
        }
      });
    }]);                                }, () {
    log('The wait is over!');
  }]);
  
  go([() {
    goSleep(1000);                      }, () {
    ch1.close();
    goSleep(1000);                      }, () {
    ch2.close();
  }]);
}

channelsTest9() {
  Channel<int> ch1 = new Channel<int>();
  Channel<int> ch2 = new Channel<int>();

  go([() {
    ch1.send(1);
    ch1.send(2);
    ch1.send(3);
    ch1.close();
    
    ch2.send(4);
    ch2.send(5);
    ch2.close();
  }]);
  
  var res = new Future.value(123);
  
  go([() {
    goWait(res);
    goForIn(ch1, [() {
      goForIn(ch2, [() {
        log('inner loop: ${$f}');
        if (res != null) {
          res = null;
          log('inner loop: res = ${$}');
        }
      }]);                            }, () {
      log('outer loop: ${$f}');
    }]);
  }]);
}
