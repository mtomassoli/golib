#Golib#

##What is it?##

**Golib** is a library which implements *goroutines* and *channels* which are the main ingredients of the *concurrency model* used by the language **Go**.

Goroutines represent functions which can be executed concurrently. For instance, if you need to perform 3 independent tasks, you can create 3 goroutines each of which performs a single task.

**Dart** is *single-threaded* so different goroutines can't be executed in parallel (if we use a single *isolate*), but every time a goroutine blocks on an operation (for instance, a read from disk), another goroutine may run.
The mechanism is similar to *multitasking* in operating systems with a single processor and a single core: different tasks seem to be running in parallel even if they aren't.
The main difference is that multitasking is preemptive, that is the OS decides when a task must be interrupted, whereas goroutines are interrupted only when they surrender control to the system.

Channels are a mean for goroutines to *communicate* and *synchronize*.
You can *send* values on a channel and *receive* values from a channel. Channels behave like *queues*, that is messages are sent/received in FIFO order. Since operations on channels may block, they can also be used as *high-level* synchronization constructs.

##Why?##

Let's say you want to write a *web server* which needs to handle many requests at once.

A first idea is to create one *thread* for each request. Unfortunately, threads are usually *heavy* so you can't create many of them.
**Pros**: code is easy to reason about.
**Cons**: code is inefficient

Another idea is to use a single thread with *asynchronous* operations. **Dart** employs this model.
**Pros**: code is efficient.
**Cons**: code is *hard* to reason about.

There is an alternative which gets the best of both world: goroutines with *synchronous* operations.
**Pros**: code is efficient *and* code is easy to reason about.

##How does Golib work?##

**Dart** doesn't have *continuations*, *coroutines* or similar, so how can we implement goroutines in it?
Well, we have to insert *breaks* manually. What is a break?
Let me show you an example. Consider the following code:

```dart
main() {
  GoFuture v;
  go([() {
    v = goWait(funcWhichReturnsAFuture());       }, () {
    print(v.value);
  }]);
}
```

That `}, () {` is what I call a break.

Briefly, *go* creates a new goroutine (which has two blocks of code), *goWait* waits for the future returned by *funcWhichReturnsAFuture* to complete, and, finally, *v.value* is the value the future completed with.

Here's what happens in (much) more detail:
1. main() starts
2. *go* creates a goroutine and schedules its execution
3. main() ends
4. the goroutine begins executing
5. the goroutine executes the first block of code (line 4):
   1. *funcWhichReturnsAFuture* returns a Future *f*
   2. *goWait* asks the goroutine to wait for *f*
   3. *goWait* creates a GoFuture *gf* which wraps *f*
   4. *goWait* returns *gf* which is assigned to *v*
6. the goroutine executes `f.then(...)` (in order to be called when *f* completes) and exits
7. *f* completes with the value *x*
8. *gf* is updated so that:
  * `v.isCompleted` is true
  * `v.value` is equal to *x*
9. the goroutine is called again
10. the goroutine executes the second block of code (line 5) which print *x*

Basically, `goWait` tells the goroutine that there is a future it likes to wait for.
When there is a break and the goroutine regains control, the goroutine notices that there is a future to wait for, so it asks the future itself to be called when the future is completed.
Once the goroutine is called again, it can execute the next block of code.

Now consider this code:

```dart
gf1 = goWait(future1);
gf2 = goWait(future2);
gf3 = goWait(future3);                       }, () {
print(gf1.value);
print(gf2.value);
print(gf3.value);
```

Interestingly, three futures are signaled to the goroutine so, when the break gives control back to the goroutine, the goroutine decides to wait for all three futures at once.
When all the futures complete, the execution continues with the second block of code.
By now, *gf1*, *gf2* and *gf3* have been updated.

If you want to use **Golib** you need to understand where to insert breaks and the only way to do that reliably is to understand how **Golib** works.

The most important thing to keep in mind is that **Golib**, under the hood, uses Futures and is *highly* asynchronous.

Here's another example:

```dart
go([() {
  print('A');
  goForever([() {
    // this code is executed forever
  }]);                                }, () {
  print('B');
}]);
```

When *go* is executed
1. it creates a new goroutine
1. it adds a new *execution frame*, which contains the blocks of code passed to *go*, to the goroutine
2. it schedules its next execution through **scheduleMicrotask**
3. it returns

When the goroutine regains control, it starts executing its blocks of code.
*goForever* is similar to *go*. The code in the loop is **not** executed when *goForever* is executed. When *goForever* is first called, this is what happens:
1. *goForever* adds a new *execution frame* to the goroutine
2. *goForever* returns

If that break were absent, `print('B')` would be executed immediately.
But since there is a break, the goroutine regains control, notices that there is a new *execution frame* and starts executing the code in it.
The loop is infinite, but, actually, we can break out of it with a `return goBreak;`.
If we ask to quit the loop, the goroutine removes the *execution frame* of the loop and resumes the execution of the previous *execution frame*, that is it executes `print('B')`.

Surprisingly enough, one can get away with way less breaks (`}, () {`) than one would expect. If you don't believe me, have a look at the example in the next section.

##Example 1##

This example shows a *client* and a *server* which communicate between them.
This example is in the file **/example/example1.dart**.

###Client###

Let's look at the client first. Here's the version with raw Futures and Streams (that is, without **Golib**).

```dart
import 'dart:io';
import 'dart:convert';

client() {
  Map jsonData = {
    'name'    : 'Han Solo',
    'job'     : 'reluctant hero',
    'BFF'     : 'Chewbacca',
    'ship'    : 'Millennium Falcon',
    'weakness': 'smuggling debts'
  };

  new HttpClient().post(InternetAddress.LOOPBACK_IP_V4.host, 4049, '/file.txt')
    .then((HttpClientRequest request) {
      request.headers.contentType = ContentType.JSON;
      request.write(JSON.encode(jsonData));
      return request.close();
    }).then((HttpClientResponse response) {
      response.transform(UTF8.decoder).listen((contents) {
        print(contents);
      });
    });
}
```

As you can see, the client sends a *Post* request with some JSON content and prints the response.
Here's how you would rewrite that with **Golib**:

```dart
import 'dart:io';
import 'dart:convert';
import 'package:golib/golib.dart';

client2() {
  Map jsonData = {
    'name': 'Han Solo',
    'job': 'reluctant hero',
    'BFF': 'Chewbacca',
    'ship': 'Millennium Falcon',
    'weakness': 'smuggling debts'
  };

  go([() {
    goWait(new HttpClient().post(InternetAddress.LOOPBACK_IP_V4.host, 4049, '/file.txt'));      }, () {
    HttpClientRequest req = $;
    req.headers.contentType = ContentType.JSON;
    req.write(JSON.encode(jsonData));
    goWait(req.close());                                                                        }, () {
    HttpClientResponse res = $;
    goForIn(res.transform(UTF8.decoder), [() {
      print($f);
    }]);
  }]);
}
```

When *goWait* finishes waiting, it puts the value the future completed with in *$*, which is a special global variable. The lines

```dart
    HttpClientRequest req = $;
    HttpClientResponse res = $;
```

are there only to improve readability. We might have just used *$* directly.
*goForIn* takes a *channel* or a *stream* and starts reading values from them. Inside the loop, we can refer to the values as *$f*.
Therefore, that *goForIn* reads and prints all the values from the Stream `res.transform(UTF8.decoder)`.

###Server###

Now let's look at the server too. First, the version with raw Futures and Streams:

```dart
import 'dart:io';
import 'dart:convert';

server() {
  HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 4049).then((server) {
    server.listen((req) {

      ContentType contentType = req.headers.contentType;
      BytesBuilder builder = new BytesBuilder();

      if (req.method == 'POST' && contentType != null &&
          contentType.mimeType == 'application/json') {
        req.listen((buffer) {
          builder.add(buffer);
        }, onDone: () {
          // write to a file, get the file name from the URI
          String jsonString = UTF8.decode(builder.takeBytes());
          String filename = req.uri.pathSegments.last;
          new File(filename).writeAsString(jsonString, mode: FileMode.WRITE).then((_) {
            Map jsonData = JSON.decode(jsonString);
            req.response.statusCode = HttpStatus.OK;
            req.response.write('Wrote data for ${jsonData['name']}.');
            req.response.close();
          });
        });
      } else {
        req.response.statusCode = HttpStatus.METHOD_NOT_ALLOWED;
        req.response.write("Unsupported request: ${req.method}.");
        req.response.close();
      }
    });
  });
}
```

This server only accepts Post requests with JSON content. When it receives a Post request for a certain file, it creates that file, writes the received JSON content to it and then sends back a short text response.
Here's how the server looks like with **Golib**:

```dart
import 'dart:io';
import 'dart:convert';
import 'package:golib/golib.dart';

server2() {
  go([() {
    goWait(HttpServer.bind(InternetAddress.LOOPBACK_IP_V4, 4049));                      }, () {
    HttpServer server = $;
    
    goForIn(server, [() {
      HttpRequest req = $f;
      ContentType contentType = req.headers.contentType;
      BytesBuilder builder = new BytesBuilder();
      String jsonString;
      
      if (req.method == 'POST' && contentType != null &&
          contentType.mimeType == 'application/json') goDo([() {

        goForIn(req, [() {
          builder.add($f);
        }]);                                                                            }, () {

        // write to a file, get the file name from the URI
        jsonString = UTF8.decode(builder.takeBytes());
        String filename = req.uri.pathSegments.last;
        goWait(new File(filename).writeAsString(jsonString, mode: FileMode.WRITE));     }, () {
        
        Map jsonData = JSON.decode(jsonString);
        req.response.statusCode = HttpStatus.OK;
        req.response.write('Wrote data for ${jsonData['name']}.');
        req.response.close();
      }]);
      else {
        req.response.statusCode = HttpStatus.METHOD_NOT_ALLOWED;
        req.response.write("Unsupported request: ${req.method}.");
        req.response.close();
      }
    }]);
  }]);
}
```

Note how there are no callbacks at all!

And you've seen nothing of **Golib**. The fun begins when we start using channels to communicate between goroutines.

##Example 2##

Now let's look at a simple example (**test/workers_test.dart**) where you can see channels in action:

```dart
import 'package:golib/golib.dart';

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

main() {
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
```

It prints:
```
worker 0 received 0
worker 1 received 1
worker 0 received 2
worker 1 received 3
worker 0 received 4
worker 1 received 5
worker 0 received 6
worker 1 received 7
worker 0 received 8
worker 0 done
worker 1 received 9
worker 1 done
All done!
```

The main function creates a goroutine which:
1. creates a *WaitGroup* to wait for two workers to end their work
2. creates a channel
3. calls *populateChan* which creates a goroutine that sends messages on the channel
4. creates two workers which are represented by two goroutines
5. wait for the workers to finish their work
6. prints *All done!*

*WaitGroup* is a sinchronization object. It has an internal counter initially equal to 0. By executing `w.add(2)` we increment its count by 2. Then, `w.wait()` waits until the count is back to 0.
Each time someone executes `w.done()` the count is decremented by 1.

We've already seen *goForIn*. This time, though, it's used with a channel directly, rather than with a stream.

*populateChan* creates a goroutine which sends some messages on *ch* and then closes it.
When a channel is closed, no other data can be sent to it, so all *goForIn* reading from that channel terminate.

##Is Golib efficient?##

Quite. Here's an example (rewritten in Dart + **Golib**) taken from the talk "Go Concurrency Patterns", by Rob Pike ([slides + video](http://talks.golang.org/2012/concurrency.slide)):

```dart
import 'package:golib/golib.dart';

f(left, right) {
  var res;
  go([() {
    res = right.recv();             }, () {
    left.send(res.value + 1);
  }]);
}

main() {
  const n = 100000;
  Channel leftmost = new Channel();
  var right;
  var left = leftmost;
  for (int i = 0; i < n; ++i) {
    right = new Channel();
    f(left, right);
    left = right;
  }
  go([() { right.send(1); }]);
  var res;
  go([() {
    res = leftmost.recv();        }, () {
    print(res.value);
  }]);
}
```

This code creates a chain *g1* -> *g2* -> ... -> *gn* of 100,000 goroutines. For all *i=1, ..., n-1*, there is a channel which connects *g{i}* to *g{i+1}* (and vice versa: channels are bidirectional). The number 1 is then sent to *g1* and the result, which is 100001, read from *gn*.

As you can see by looking at *f*, each goroutine sends to the next goroutine in the chain the number it received incremented by 1.

This example takes 3 seconds in Dart + **Golib** and 1 second in Go. Not bad at all, since we're using Futures!

OK, the introduction is over and now it's time to examine **Golib** in detail. Let's start with its most important function: *go*.

##go##

The function *go* is used to create a goroutine. You can think of a goroutine as a *unit of concurrency*. You can think of them as *very* lightweight threads. Here's its signature:

```dart
void go(List<Function> blocks)
```

This function takes a list of blocks of code, schedules the execution of the goroutine (via **scheduleMicrotask**) and returns.

Consider the following example:

```dart
import 'package:golib/golib.dart';

main() {
  go([() {
    print(1);
  }]);

  go([() {
    print(2);
  }]);

  go([() {
    print(3);
  }]);
  
  print(4);
}
```

This prints:

```
4
1
2
3
```

This is what happens:
1. main starts.
2. The first *go* executes, schedules the execution of the first goroutine and returns.
3. The second *go* executes, schedules the execution of the second goroutine and returns.
4. The third *go* executes, schedules the execution of the third goroutine and returns.
5. `print(4)` is executed.
6. main ends.
7. The first goroutine executes and prints 1.
8. The second goroutine executes and prints 2.
9. The third goroutine executes and prints 3.

You can call *go* inside other goroutines:

```dart
main() {
  go([() {
    print(1);
    go([() {
      print(5);
    }]);
  }]);

  go([() {
    print(2);
  }]);

  go([() {
    print(3);
  }]);
  
  print(4);
}
```

This prints:

```
4
1
2
3
5
```

You can terminate a goroutine by returning *goExit*, like this:

```dart
main() {
  go([() {
    ...
    return goExit;
    ...
  }]);
}
```

Goroutines also support the function *defer*. That takes a *code group*, that is a list of blocks of code. When the goroutine that called *defer* ends, the code in the *code group* is executed.
Every goroutine may call *defer* more than once. In that case, the code groups are executed in LIFO order.
Note that code in code groups may also call *defer*.
*defer* can be used to defer the execution of *cleaning code*, that is code which frees resources.

Consider this pseudo-code:

```dart
import 'package:golib/golib.dart';

main() {
  go([() {
    var res1 = getResource();
    defer([() {
      release(res1);
    }]);
    
    var res2 = getResource();
    res2.attachTo(res1);
    defer([() {
      res2.detach(res1);
      release(res2);
    }]);
  }]);
}
```

Let's assume that *getResource* allocates a resource and returns it. The code suggests that the second resource, *res2*, depends on the first one, *res1*. Because of this dependency, it's important that *res2* is freed before *res1*.
This is why deferred code is executed in LIFO order.

##GoFutures##

A GoFuture is a class which wraps a Future. When the Future completes, the GoFuture is updated with the value or the error the Future completed with.
You create a GoFuture by passing a Future to its constructor:

```dart
GoFuture<int> gf = new GoFuture(future);
```

A GoFuture has the following properties:
* **isCompleted**: tells whether the GoFuture has completed.
* **hasError**: tells whether the GoFuture has completed with an error.
* **value**: the value the GoFuture completed with.
* **error**: the error the GoFuture completed with.
* **output**: the value or the error the GoFuture completed with.

A GoFuture has also the following methods:
* `static GoFuture and(List<GoFuture> fs)`:
returns a GoFuture which completes if and only if all the GoFutures in *fs* complete.
* `static GoFuture or(List<GoFuture> fs)`:
returns a GoFuture which completes if and only if at least one of the GoFutures in *fs* completes.
* `GoFuture operator*(GoFuture that)`:
returns `GoFuture.and([this, that])`. Use *and* directly when you want to combine more than two GoFutures (it's more efficient).
* `GoFuture operator+(GoFuture that)`:
returns `GoFuture.or([this, that])`. Again, use *or* directly when you want to combine more than two GoFutures (it's more efficient).

##goWait, goWaitAll, and goWaitAny##

Here are the signatures:
* `GoFuture goWait(f, [bool use$ = true])`
* `void goWaitAll(List<GoFuture> fs)`
* `void goWaitAny(List<GoFuture> fs)`

You use *goWait* when you want to wait for a Future/GoFuture to complete. The first parameter can be either a Future or a GoFuture. If it's a Future, it's wrapped into a GoFuture and that GoFuture is returned. If it's a GoFuture, that GoFuture is returned directly.

**IMPORTANT:**
* Put a **break** after *goWait*.
* Do **NOT** call *goWait* outside of a goroutine

###How it works###

*goWait* adds a Future/GoFuture to the *completion list* of the current goroutine. When there is a break, the goroutine regains control and checks the completion list. If the list is empty, it goes on executing other blocks of code. If the list is not empty, the goroutine waits for the completion of all the Futures in the completion list. Only when *all* the Futures have completed, does the execution continue with the next block of code.

This implies a few things:
1. You don't need to break immediately after a single *goWait*.
2. You can break once after a series of *goWait*.
3. Between a *goWait(f)* and, say, a `print(f.value)` there must be a break.

In what follows, let *f* be a Future. You can use *goWait* many ways:

1)
```dart
GoFuture gf;
go([() {
  gf = new GoFuture(f);
  goWait(gf);                                   }, () {
  if (gf.hasError)
    print('error = ${gf.error}');
  else
    print('value = ${gf.value}');
}]);
```

2)
```dart
GoFuture gf;
go([() {
  gf = goWait(f);                               }, () {
  if (gf.hasError)
    print('error = ${gf.error}');
  else
    print('value = ${gf.value}');
}]);
```

3)
```dart
go([() {
  goWait(f);                                    }, () {
  if ($err)
    print('error = ${$}');
  else
    print('value = ${$}');
}]);
```

1) is equivalent to 2) because if you pass a Future to *goWait*, it returns a GoFuture which wraps the Future. If you pass *goWait* a GoFuture, it'll return that GoFuture.
3) works because *goWait* also updates two global variables:
* **$**: contains the value or the error the GoFuture completed with
* **$err**: boolean which tells whether the GoFuture completed with an error

**IMPORTANT:
 If you want *gf* to be visible in both blocks of code, you must declare that outside the goroutine (that's what we did in 1) and 2)).**

As we said, you can call *goWait* multiple times and break just once at the end, or you can call *goWaitAll*. These two pieces of code are equivalent:

1)
```dart
go([() {
  goWait(gf1);
  goWait(gf2);
  goWait(gf3);                                    }, () {
  print(gf1.value + gf2.value + gf3.value);
}]);
```

2)
```dart
go([() {
  goWaitAll([gf1, gf2, gf3]);                     }, () {
  print(gf1.value + gf2.value + gf3.value);
}]);
```

While *goWaitAll* waits for *all* the GoFuture to complete, *goWaitAny* waits until at least one of the GoFuture completes.
Consider the following code:

```dart
go[() {
  goWait(a);
  goWaitAny([b, c, d]);
  goWaitAll([e, f]);                  }, () {
  ...
}]);
```

After the break, the goroutine waits for the goFuture
`GoFuture.and([a, GoFuture.or([b, c, d]), e, f])`
to complete.
Note that when that GoFuture will have completed, *a*, *e* and *f* will have also completed, but *b*, *c* and *d* might not have all completed.
If you access the properties *value* and *error* of an uncompleted GoFuture, a *UsageException* is thrown. You must check *isCompleted*.

##Control Flow##

**Golib** defines the following Control Flow constructs:
* goWhile
* goForever
* goDo
* goBody
* goForIn
* goSelect

*goDo* and *goBody* are not real control flow constructs, as we'll see in a moment.

**IMPORTANT: All these functions can only be used inside goroutines.**

I'll describe them one by one.

###goWhile###

*goWhile* is a function with the following signature:

```dart
void goWhile(bool cond(), List<Function> blocks, [List<Function> incBlocks = null])
```

Here's an example:

```dart
import 'package:golib/golib.dart';

main() {
  go([() {
    int i = 0;
    goWhile(() => i < 3, [() {
      int j = 0;
      goWhile(() => j < 2, [() {
        print('i: $i, j: $j');
        j++;
      }]);                             }, () {
      i++;
    }]);
  }]);
}
```

This prints:

```
i: 0, j: 0
i: 0, j: 1
i: 1, j: 0
i: 1, j: 1
i: 2, j: 0
i: 2, j: 1
```

The example above is not a good example because there's no need to use *goWhile*! If you don't need breaks inside the loop, you don't need *goWhile*.
This is perfectly OK:

```dart
main() {
  go([() {
    for (int i = 0; i < 3; i++)
      for (int j = 0; j < 2; j++)
        print('i: $i, j: $j');
  }]);
}
``` 

Let's modify the example so that the two *goWhile* are needed:

```dart
import 'package:golib/golib.dart';

main() {
  go([() {
    int i = 0;
    goWhile(() => i < 3, [() {
      int j = 0;
      goWhile(() => j < 2, [() {
        print('i: $i, j: $j');
        j++;
        goSleep(500);
      }]);                             }, () {
      i++;
    }]);
  }]);
}
```

Now, each iteration has a half-second delay.

*goSleep* is implemented as follows:

```dart
void goSleep(int milliseconds) {
  if (!_insideGo)
    throw new UsageException("You can't use goSleep outside of a goroutine!");

  goWait(new Future.delayed(new Duration(milliseconds: milliseconds)),
         false);        // false = doesn't modify $
}
```

As you can see, it pauses execution for a specified number of milliseconds. Of course, for it to work, you need to put a break after *goSleep*.

As I mentioned in the introduction, *goWhile* doesn't execute the code of *blocks* when it's called. What happens is that *goWhile* adds an *execution context* to the current goroutine and then returns. At this point, the goroutine must regain control. For this to happen, there must be a break right after the *goWhile*.

If we removed the break from the code above, `i++` would be executed before the code inside the inner *goWhile*. In fact, *goWhile* just tells the goroutine that there is a new execution context and returns. It's only after a break that the goroutine regains control, notices the new execution context and starts executing code blocks in it.

Why isn't there any break after the outer *goWhile*? Because there's an implicit break: the code block of the goroutine ends.
The same can be said for *goSleep*: the block of the inner *goWhile* ends so there is an implicit break. This is why the inner loop must be a *goWhile* and not simply a regular while loop: we need a break, implicit or explicit, after *goSleep*.

Let's see in detail how the entire code executes:
1. main starts.
2. go creates a goroutine with a single block of code and returns.
3. main ends.
4. The goroutine gains control and starts executing its block of code.
5. goWhile adds another *execution context* with two blocks of code and returns.
6. The goroutine regains control, sees the new execution context and starts executing its first block of code.
7. The inner goWhile adds another *execution context* with just one block of code and returns.
8. The current block of code ends (thanks to the break).
9. The goroutine regains control, sees the new execution context and starts executing its block of code.
10. goSleep tells the goroutine to wait for a Future which will complete in half a second.
11. The block of code (containing goSleep) ends.
12. The goroutine regains control, notices there is a Future to wait for, so schedules a new execution for when the Future has completed, and exits.
14. (... other goroutines execute if any...)
15. The Future completes.
16. The goroutine regains control and starts another iteration of the inner loop...
17. etc...

I hope you get the idea of how all this process works.

*goWhile* also takes an optional parameter. You can use it when you need to execute some blocks of code (like the increment statement in a regular for loop) at the end of each iteration of the loop.

*goWhile* supports *break* and *continue* like regular while loops, but you need to use a return statement. That's needed because you must return the right value back to the goroutine which is executing the current block of code.

Here's a variation of the previous example:

```dart
import 'package:golib/golib.dart';

main() {
  go([() {
    int i = 0;
    goWhile(() => i < 3, [() {
      int j = 0;
      goWhile(() => j < 2, [() {
        if (i + j > 2)
          return goBreak;
        print('i: $i, j: $j');
        j++;
        goSleep(500);
      }]);                             }, () {
      i++;
    }]);
  }]);
}
```

Now the code prints:

```
i: 0, j: 0
i: 0, j: 1
i: 1, j: 0
i: 1, j: 1
i: 2, j: 0
```

Note that it prints one line less than the previous code.

To skip to the next iteration, just return `goContinue` rather than `goBreak`.

###goForever###

*goForever* is a function with the following signature:

```dart
void goForever(List<Function> blocks, [List<Function> incBlocks = null])
```

*goForever* is just a *goWhile* whose *cond* is always true. The same rules apply so remember to insert a break just after the *goForever*, if there isn't already an implicit one.

###goDo###

*goDo* is used with *if-else* statements. For example:

```dart
import 'package:golib/golib.dart';

main() {
  go([() {
    int i = 4;
    if (i > 3) goDo([() {
      goSleep(1000);                }, () {
      print('i > 3');
      goSleep(1000);
    }]);
    else if (i < 3)
      print('i < 3');
    else goDo([() {
      print('i = 3');
      goSleep(500);
    }]);                            }, () {
    
    print('end');
  }]);
}
```

As with *goWhile*, you use *goDo* only when you need a break inside an if branch. For instance, the *else if* in the middle doesn't use a *goDo* because it isn't necessary.
What about the last *else*? Well, it doesn't need a *goDo* because there is no explicit break, so we could just write:

```dart
import 'package:golib/golib.dart';

main() {
  go([() {
    int i = 4;
    if (i > 3) goDo([() {
      goSleep(1000);                }, () {
      print('i > 3');
      goSleep(1000);
    }]);
    else if (i < 3)
      print('i < 3');
    else {
      print('i = 3');
      goSleep(500);
    }                               }, () {
    
    print('end');
  }]);
}
```

**IMPORTANT:**
Here we said that the last *goDo* is not needed because there is no explicit break, but we said before that *goWhile* is needed even when there is no explicit break. Why is that?
The problem is that the code in a loop is executed multiple times and if we call, for instance, *goSleep* at the end of the cycle, we still need a break before the next cycle begins. If we used a regular while loop, all cycles would be executed without a single break between them.
With *goDo* the situation is different because its code is executed just once and after *goDo* there is a break, so there is no need to put a break also inside the code passed to *goDo*.
Anyway, remember that adding extra breaks never hurts. It's just a little less efficient.


As always, the break after the entire *if ... else if ... else ...* is needed.
This is what happens if we don't put it:
1. i > 3 so the first branch is taken.
2. *goDo* is called, it creates a new *execution frame* with two blocks of code, and returns.
3. `print('end')` is executed!
4. The goroutine regains control, notices a new execution frame and executes its first block of code.
5. etc...

If there is a break before `print('end')` as in the example above, the goroutine regains control before `print('end')` is executed, notices the execution frame added by *goDo* and executes its first block of code.
`print('end')` will be executed at the end, since it's the second block of code of the goroutine.

Before you ask, no, you can't use *goDo* with normal *while* and *for* loops. It just can't work! The loop would execute *goDo* multiple times creating multiple execution frames, but the code passed to *goDo* would only be executed at the end of the loop, after a break!
Even worse, the condition of the loop might depend on the code passed to *goDo* and thus the loop might never end.

###goBody###

If you need a function whose code has one or more breaks, you need to define a *special* function.
Here's an example:

```dart
// void function (goReturn is optional).
void go_func1(int x) {
  int i = 1;
  int j = 2;
  goBody([() {
    ...
    return goReturn;
    ...
  }]);
}

// non-void function (goReturn is mandatory).
ReturnValue<String> go_func2(int x) {
  int i = 3;
  int j = 4;
  return goBody([() {
    ...
    return goReturn("$i, $j");
    ...
  }]);
}

var ret;
go([() {
  go_func1(1);                        }, () {     // must break!
  ret = go_func2(2);                  }, () {     // must break!
  print(ret.value);
}]);
```

Here are the important points to remember:
* You can declare variables before *goBody*.
* If you're writing a *void* function, `return goReturn` is optional (like in normal functions).
* If you're writing a *non-void* function, you need to use `return goReturn(...)` to return a value.
* In *non-void* functions, you must return the value returned by *goBody* (`return goBody([() { ...`).
* *non-void* functions must return instances of ReturnValue.
* You must break after you call this kind of function.
* You can access the return value through the property *value*.

###goForIn and goSelect###

I prefer to talk about these two control flow functions after I've introduced *channels*.

##WaitGroup##

A *WaitGroup* is a simple synchronization class which has the following methods:
* `void add(int delta)`
Increments the counter by *delta* (Note: *delta* may be negative).
* `void done()`
Decrements the counter by 1.
* `void wait()`
Waits until the counter is 0.

A *WaitGroup* has a *counter* which is initially 0. This counter can never become negative or a UsageException will be thrown.
*wait* waits until the counter is 0. As always, you must put a break after you call *wait*.

Consider this example:

```dart
import 'package:golib/golib.dart';

main() {
  WaitGroup w = new WaitGroup();
  w.add(2);
  
  go([() {
    print(1);
    goSleep(1000);          }, () {
    w.done();
  }]);

  go([() {
    print(2);
    goSleep(1000);          }, () {
    w.done();
  }]);

  go([() {
    w.wait();               }, () {
    print('All done!');
  }]);
}
```

It prints:

```
1
2
All done!
```

The two numbers are printed immediately, while 'All done!' is printed after one second.
Initially, the counter of *w* is 0. We increment it by 2 with `w.add(2)`. Note that the counter must be incremented before `w.done()` is called. That's why we call *add* in the main function and not at the beginning of the third goroutine.
After main returns, the three goroutines start running and the third one waits for the first two to finish their work.

##Channels##

*Channels* are the most complex objects in **Golib**. Think of a Channel as a FIFO *queue*. You can *send* a value on a channel and *recv* (receive) a value from it. These operations can *block*. Here, *blocking* means that a request of *waiting* is sent to the goroutine. The wait is honored only after a break, as always.

Basically, a blocking *send* or *recv* behaves like a *goWait*. Also note that breaks after non-blocking *sends* and *recvs* are ignored. This means that the goroutine goes on executing the next block of code immediately. If you're sure that an operation doesn't block, you don't need any break. If an operation can block, you need a break.

You create a channel with

```dart
Channel ch = new Channel(dim);
```

The signature of the constructor is:

```dart
Channel([int dim = 0])
```

where *dim* is the dimension of the channel. A channel has an internal *queue* of length *dim*. If *dim* is *Channel.infinite*, the channel has infinite length.

###send and recv###

Here are the signatures of *send* and *recv* operations:

```dart
bool send(E newVal, [bool doNotBlock = false])
GoFuture<E> recv([bool doNotBlock = false])
```

Both operations may block. An operation blocks when it cannot proceed until something else happens.

Here are the **rules for *send***:
* If the channel is full (it contains *dim* elements) and there are no *recv* operations pending, *send* blocks.
* If there are *recv* operations pending, *send* unblocks the oldest pending *recv* operation and returns without blocking.
* If the channel is *closed*, *send* throws a UsageException (I'll talk about closing channels later).
* If *send* needs to block and *doNotBlock* is true, it returns false without blocking and doing anything.

Note that if *dim* is 0 and there are no *recv* pending, *send* always blocks. Channels with *dim* equal to 0 are usually called *unbuffered*.

Of course, if you call *send* with *doNotBlock* equal to true, the operation won't block no matter what. If the operation needs to block, it simply fails and returns false.

Here are the **rules for *recv***:
* If the channel is empty (it contains 0 elements) and there are no *send* operations pending, *recv* blocks.
* If the channel is not empty, *recv* returns the first value on the internal *queue*. If there are *send* operations pending, it means that the *queue* was full. Now that the *queue* has one free spot, the oldest *send* operation is unblocked and its valued added to the *queue*.
* If the channel is empty but there are *send* operations pending, *recv* unblocks the oldest pending *send* operation and returns its value.
* If the channel is *closed*, *recv* returns *channelClosed* without blocking.
* If *recv* needs to block and *doNotblock* is true, it returns null without blocking and doing anything.

*recv* always returns a GoFuture (or null). If *recv* blocks then the returned GoFuture will complete only after a break. If *recv* doesn't block, you can use the GoFuture immediately. Anyway, you can always check whether the GoFuture has completed by reading the property *isCompleted* of the GoFuture.

###Example###

```dart
import 'package:golib/golib.dart';

main() {
  Channel<int> c = new Channel();     // unbuffered channel

  {
    go([() {
        print('A1');
        c.send(1);
        c.send(2);                      }, () {
        print('A2');
        c.send(3);                      }, () {
        print('A3');
    }]);
  }

  {
    GoFuture v1, v2, v3;

    go([() {
        print('B1');
        v1 = c.recv();
        v2 = c.recv();                  }, () {
        print('B2');
        v3 = c.recv();                  }, () {
        print('B3');
        print(v1.value);
        print(v2.value);
        print(v3.value);
    }]);
  }
}
```

This prints

```
A1
B1
B2
A2
A3
B3
1
2
3
```

In this example, the first goroutine starts first because it gets scheduled before the other one, but it's better not to depend on this implementation details because they might change in the future.
Anyway, this is what happens:
1. The first goroutine is scheduled.
2. The second goroutine is scheduled.
3. main ends.
4. The first goroutine starts.
5. `print('A1')` is executed.
6. `c.send(1)`: needs to block because *c* is full (*dim* is 0).
7. `c.send(2)`: needs to block.
8. First break.
9. The first goroutine starts waiting for the two send.
10. The second goroutine starts.
11. `print('B1')` is executed.
12. `v1 = c.recv()`: reads *v1*, unblocks the first send and returns without blocking.
13. `v2 = c.recv()`: reads *v2*, unblocks the second send and returns without blocking.
14. Break.
15. The second goroutine sees that there is nothing to wait for, so goes on executing the next block of code.
16. `print('B2')` is executed.
17. `v3 = c.recv()`: needs to block because *c* is empty.
18. Break.
19. The second goroutine starts waiting for the pending recv operation.
20. The first goroutine resumes execution.
21. `print('A2')` is executed.
22. `c.send(3)`: unblocks the recv operation pending and returns without blocking.
23. Break.
24. The first goroutine sees that there is nothing to wait for, so goes on executing the next block of code.
25. `print('A3')` is executed.
26. The first goroutine ends.
27. The second goroutine resumes execution.
28. `print('B3')` is executed.
29. `print(v1.value)`: prints 1.
30. `print(v2.value)`: prints 2.
31. `print(v3.value)`: prints 3.
32. The second goroutine ends.

###Closing a channel###

A channel can be closed by calling the method *close*. When a channel is closed, no more values can be sent on it (if you try, a UsageException is thrown) and any *recv* operation will return *channelClosed*.
Note that *close* unblocks any pending *recv* operations on the same channel. No *recv* operation can block on a closed channel. It just returns *channelClosed* immediately without blocking (you still need to read the *value* property of the GoFuture).

###ROChannel and WOChannel###

*ROChannel* is a read-only channel, whereas *WOChannel* is a write-only channel. *Channel* implements both *ROChannel* and *WOChannel* so you can pass an instance of Channel to a function which requires a *ROChannel* or a *WOChannel*.
This is useful when you want that the compiler checks for you that only read (or write) operations are performed on a channel.

###nil###

*nil* is a special channel. Every operation on *nil* blocks indefinitely. Look at the section about *goSelect* for an example of its usage.

###Streams and channels###

Streams can be attached to a channel. Attached streams send values on a channel but always without blocking. This means that if a channel is full, values will be lost. There are two solutions to this problem:
1. Create an *infinite* channel.
2. Recv data frequently so that the channel doesn't fill up.

You can attach streams to channels and detach them by using the following constructors and methods:

1. `Channel.attached(Stream stream, {int dim: infinite, bool detachOnError: false, bool reportErrors: false})`
Creates a channel and attaches *stream* to it (see *attach* for the other parameters).

2. `Channel.attachedAll(List<Stream> streams, {int dim: infinite, bool detachOnError: false, bool reportErrors: false})`
Creates a channel and attaches all the stream in *streams* to it (see *attach* for the other parameters).

3. `void attach(Stream stream, {bool detachOnError: false, bool reportErrors: false})`
Attaches *stream* to the channel.
If *detachOnError* is true, if and when *stream* sends an error, *stream* is detached from the channel.
If *reportErrors* is false, the errors sent by *stream* are ignored and not sent on the channel. Errors are wrapped in the object *StreamError* so that you can spot them.

4. `void attachAll(List<Stream> streams, {bool detachOnError: false, bool reportErrors: false})`
Attaches all the streams in *streams* to the channel (see *attach* for the parameters).

5. `void detach(Stream stream)`
Detaches *stream* from the channel.

6. `void detachAll()`
Detaches all the streams currently attached to the channel.

**IMPORTANT:**
* When you *close* a channel, all streams are detached.
* When a stream is closed, it's automatically detached from the channel.
* If *closeWhenStreamsDone* (a property you can modify) is true, when the last attached stream is closed, the channel is automatically closed.
* *closeWhenStreamsDone* is initially true.

For an example, look at the next section.

###goForIn###

*goForIn* is a *for-in* loop which works with channels. The syntax is simple:

```dart
goForIn(ch, [() {
  print($f);
}]);
```

*goForIn* reads elements from *ch* one by one and, for each value read, assigns that value to the variable *$f* and executes the blocks of code provided by the user.
*goForIn* stops when *ch* is closed.

*goForIn* can also read from streams. Just pass it the stream instead of the channel. Internally, *goForIn* creates a channel and attaches the stream to it, but that's just an implementation detail. 

**IMPORTANT:** as always, put a break after *goForIn*.

Here's an example:

```dart
import 'dart:async';
import 'package:golib/golib.dart';

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

main() {
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
```

*timedCounter(duration, max)* returns a stream that produces the sequence *1, 2, ..., max*, where *duration* is the amount of time between the generation of successive elements.

###goSelect###

*goSelect* is similar to a *switch* statement, but works with channels and GoFuture. You use *goSelect* to choose between a series of channel operations and futures.

Here's the general syntax:

```dart
goSelect(() {
  var v;
  if (goCase(v = ch1.recv())) goDo([() {
    ... 
  }]);
  else if (goCase(v = ch1.recv(), future, ch3.send(v))) {
    ...
  }
  else if (goCase(v = ch1.recv(), sendOn(ch4))) {
    <some non-blocking computation>
    ch4.send(123);              // non-blocking
    ...
  }
  else if (goDefault()) {
    ...
  }
}                     // <---------- remember to put a break here!!!
```

Let's say a branch is non-blocking when all its channel operations are non-blocking and all its GoFuture are already completed.

If no branches are non-blocking,
1. if there is a default case (*goDefault*), that branch is taken;
2. if there isn't a default case, *goSelect* blocks.

If one branch is non-blocking, *goSelect* takes that branch.
If more than one branch is non-blocking, *goSelect* selects one at random.

If *goSelect* is blocked, it unblocks when at least a branch can be taken.

Note that:
* You may declare variables at the beginning of a *goSelect*.
* You **MUST** use *goCase* to wrap operations.
* You can use *goDo* to introduce a branch with breaks.
* *goDefault* is optional.
* You can specify both *futures* (instances of GoFuture) and channel operations.
* You can specify multiple operations in a single *goCase*.
* Operations of the form `v = ch1.recv()` and `ch3.send(v)`, are executed right before the corresponding branch is taken (when both are non-blocking, of course).
* Operations of the form `sendOn(ch)` and `recvFrom(ch)` are indicated but not executed. If the corresponding branch is taken, they can be used (once) without blocking. If, however, you put a break before you use them, all bets are off (that is, they *can* block).
Look at the example above: a send is indicated through `sendOn(ch4)` and it's executed in the code of the corresponding branch (`ch4.send(123)`).
On the contrary, `v = ch1.recv()` is executed right before the code in the corresponding branch is executed.
* Operations in a single *goCase* are executed from left to right. For instance, in `goCase(v = ch1.recv(), future, ch3.send(v))`, *v* is received from *ch1* and sent on *ch3*.
* A *goCase* can't have repeated operations or GoFuture (note that `sendOn(ch4)` and `ch4.send(1)` are the same operation!).
* A branch is taken when all its operations are non-blocking and all its GoFuture are completed. The operations are considered individually, that is, `ch1.send(1)` and `ch1.recv()` will still block even if *together* they would proceed because one would unblock the other.

###Example 1###

```dart
import 'package:golib/golib.dart';

main() {
  Channel<int> ch1 = new Channel<int>();
  Channel<int> ch2 = new Channel<int>();
  
  go([() {
    int i = 0;
    goWhile(() => i++ < 2, [() {
      goSelect(() {
        var x;
        if (goCase(x = ch1.recv())) {
          ch1 = nil;
          print('ch1 is now nil');
        }
        else if (goCase(x = ch2.recv())) {
          ch2 = nil;
          print('ch2 is now nil');
        }
      });
    }]);                                }, () {
    print('The wait is over!');
  }]);
  
  go([() {
    goSleep(1000);                      }, () {
    ch1.close();
    goSleep(1000);                      }, () {
    ch2.close();
  }]);
}
```

It prints

```
ch1 is now nil
ch2 is now nil
The wait is over!
```

Initially, *goSelect* blocks because both `x = ch1.recv()` and `x = ch2.recv()` are blocking and there is no default case.
When, after a pause of 1 second, *ch1* is closed, the first branch of *goSelect* is taken, `ch1 = nil` is executed and "ch1 is now nil" is printed.
Since any operation on *nil* blocks, the first branch is virtually removed from *goSelect*. If we removed `ch1 = nil`, on the next iteration the first branch would be immediately taken because a recv on a closed channel never blocks (it reads the value *channelClosed*).

###Example 2###

```dart
import 'dart:async';
import 'package:golib/golib.dart';

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

main() {
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
            print('ch1: ${v.value}');
          else
            ch1 = nil;
        }
        else if (goCase(v = ch2.recv())) {
          if (v.value != channelClosed)
            print('ch2: ${v.value}');
          else
            ch2 = nil;
        }
        else if (goCase(v = ch3.recv())) {
          if (v.value != channelClosed)
            print('ch3: ${v.value}');
          else
            ch3 = nil;
        }
      });
    }]);                                            }, () {
    print('done');
  }]);
}
```

This example is more involved. As you can see, three streams are attached to three channels and a *goSelect* is used to read from them.
Here are the key points:
* The loop ends only when *ch1*, *ch2* and *ch3* are all *nil*.
* When a `v = chX.recv()` is non-blocking, the operation is performed and the code in the corresponding branch:
  * prints a message if *chX* is not closed or
  * executes `chX = nil` if *chX* is closed.

Basically, when a channel is closed, the branch related to it is virtually removed from *goSelect* with the *nil trick*.

##That's all for now!##
