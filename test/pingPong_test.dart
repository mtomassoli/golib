part of test;

void registerPingPongTests() {
  registerTest(new Test(
      'pingPongTest',
      pingPongTest,
      'ping 1|pong 2|ping 3|pong 4|ping 5|pong 6|ping 7|pong 8|ping 9|pong 10|'
      'ping 11|'
  ));
}

/* Go code taken from "Advanced Go Concurrency Patterns" by Sameer Ajmani
   (http://talks.golang.org/2013/advconc.slide)

type Ball struct{ hits int }

func main() {
    table := make(chan *Ball)
    go player("ping", table)
    go player("pong", table)

    table <- new(Ball) // game on; toss the ball
    time.Sleep(1 * time.Second)
    <-table // game over; grab the ball
}

func player(name string, table chan *Ball) {
    for {
        ball := <-table
        ball.hits++
        fmt.Println(name, ball.hits)
        time.Sleep(100 * time.Millisecond)
        table <- ball
    }
}

*/

class Ball { int hits = 0; }

void player(String name, Channel<Ball> table) {
  var ball;
  go([() {
    goForever([() {
      ball = table.pop();                     }, () {
      if (ball.value == channelClosed)
        return goExit;
      ball.value.hits++;
      log('$name ${ball.value.hits}');
      goSleep(100);                           }, () {
      table.push(ball.value);
    }]);
  }]);
}

pingPongTest() {
  var table = new Channel<Ball>();
  go([() {
    player('ping', table);
    player('pong', table);
    
    table.push(new Ball());
    goSleep(1000);                            }, () {
    table.pop();                              }, () {
    table.close();
  }]);
}
