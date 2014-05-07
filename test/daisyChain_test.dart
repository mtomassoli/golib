part of test;

void registerDaisyChainTests() {
  registerTest(new Test(
      'daisyChainTest',
      daisyChainTest,
      '100001|'
  ));
}

/* Go code taken from the talk "Go Concurrency Patterns", by Rob Pike
   (http://talks.golang.org/2012/concurrency.slide)

func f(left, right chan int) {
    left <- 1 + <-right
}

func main() {
    const n = 10000
    leftmost := make(chan int)
    right := leftmost
    left := leftmost
    for i := 0; i < n; i++ {
        right = make(chan int)
        go f(left, right)
        left = right
    }
    go func(c chan int) { c <- 1 }(right)
    fmt.Println(<-leftmost)
}

*/

f(left, right) {
  var res;
  go([() {
    res = right.pop();              }, () {
    left.push(res.value + 1);
  }]);
}

daisyChainTest() {
  const n = 100000;
  Channel leftmost = new Channel();
  var right;
  var left = leftmost;
  for (int i = 0; i < n; ++i) {
    right = new Channel();
    f(left, right);
    left = right;
  }
  go([() { right.push(1); }]);
  var res;
  go([() {
    res = leftmost.pop();         }, () {
    log(res.value);
  }]);
}
