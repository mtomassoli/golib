import 'dart:io';
import 'dart:convert';
import 'package:golib/golib.dart';

// This is an example taken from "Write HTTP Clients & Servers"
// (https://www.dartlang.org/docs/tutorials/httpserver/)

//------------------------------------------------------------------
// Using raw Futures and Streams
//------------------------------------------------------------------

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

//------------------------------------------------------------------
// Using golib
//------------------------------------------------------------------

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
        
        return goBreak;           // stops the server
      }]);
      else {
        req.response.statusCode = HttpStatus.METHOD_NOT_ALLOWED;
        req.response.write("Unsupported request: ${req.method}.");
        req.response.close();
      }
    }]);
  }]);
}

main() {
  server2();
  client2();
}
