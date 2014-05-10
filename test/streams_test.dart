part of test;

void registerStreamsTests() {
  registerTest(new Test(
      'streamsTest1',
      streamsTest1,
      'library test;|'
  ));

  registerTest(new Test(
      'streamsTest2',
      streamsTest2,
      '1|1|2|3|1|2|4|5|3|6|7|2|4|8|9|5|10|11|3|6|12|13|7|14|15|4|8|16|17|9|18|19|'
      '5|10|20|'
  ));

  registerTest(new Test(
      'streamsTest3',
      streamsTest3,
      (String s) {
        var lines = s.split('|');
        return lines.length == 37 && lines[lines.length - 2] == 'done';
      }
  ));
}

/* With raw streams. 

streamsTest() {
  List result = [];

  Stream<List<int>> stream = new File(Platform.script.toFilePath()).openRead();
  int semicolon = ';'.codeUnitAt(0);
  StreamSubscription subscription;
  subscription = stream.listen((data) {
    for (int i = 0; i < data.length; i++) {
      result.add(data[i]);
      if (data[i] == semicolon) {
        print(new String.fromCharCodes(result));
        subscription.cancel();
        return;
      }
    }
  });
}
*/

streamsTest1() {
  List result = [];
  int semicolon = ';'.codeUnitAt(0);
  Channel ch = new Channel(Channel.infinite);

  go([() {
    ch.attach(new File(Platform.script.toFilePath()).openRead());
    goForIn(ch, [() {
      for (int i = 0; i < $f.length; i++) {
        result.add($f[i]);
        if ($f[i] == semicolon) {
          log(new String.fromCharCodes(result));
          ch.close();
          break;
        }
      }
    }]);
  }]);
}

// Taken from "Creating Streams in Dart"
// (https://www.dartlang.org/articles/creating-streams/)
Stream<int> timedCounter(Duration interval, [int maxCount]) {
  StreamController<int> controller;
  Timer timer;
  int counter = 0;
  
  void tick(_) {
    counter++;
    controller.add(counter); // Ask stream to send counter values as event.
    if (maxCount != null && counter >= maxCount) {
      timer.cancel();
      controller.close();    // Ask stream to shut down and tell listeners.
    }
  }
  
  void startTimer() {
    timer = new Timer.periodic(interval, tick);
  }

  void stopTimer() {
    if (timer != null) {
      timer.cancel();
      timer = null;
    }
  }

  controller = new StreamController<int>(
      onListen: startTimer,
      onPause: stopTimer,
      onResume: startTimer,
      onCancel: stopTimer);

  return controller.stream;
}

streamsTest2() {
  Stream s1 = timedCounter(const Duration(milliseconds: 200), 5);
  Stream s2 = timedCounter(const Duration(milliseconds: 100), 10);
  Stream s3 = timedCounter(const Duration(milliseconds: 50), 20);
  Channel ch = new Channel.attachedAll([s1, s2, s3]);
  go([() {
    goForIn(ch, [() {
      log($f);
    }]);
  }]);
}

streamsTest3() {
  Stream s1 = timedCounter(const Duration(milliseconds: 200), 5);
  Stream s2 = timedCounter(const Duration(milliseconds: 100), 10);
  Stream s3 = timedCounter(const Duration(milliseconds: 50), 20);
  Channel ch1 = new Channel.attached(s1);
  Channel ch2 = new Channel.attached(s2);
  Channel ch3 = new Channel.attached(s3);
  go([() {
    goWhile(() => ch1 != nil || ch2 != nil || ch3 != nil, [() {
      goSelect(() {
        var v;
        if (goCase(v = ch1.recv())) {
          if (v.value != channelClosed)
            log('ch1: ${v.value}');
          else
            ch1 = nil;
        }
        else if (goCase(v = ch2.recv())) {
          if (v.value != channelClosed)
            log('ch2: ${v.value}');
          else
            ch2 = nil;
        }
        else if (goCase(v = ch3.recv())) {
          if (v.value != channelClosed)
            log('ch3: ${v.value}');
          else
            ch3 = nil;
        }
      });
    }]);                                            }, () {
    log('done');
  }]);
}
