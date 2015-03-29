import 'package:unittest/unittest.dart';
import '../bin/dart2dserver.dart';
import 'package:dart2dserver/sessions.dart';
import 'dart:async';

Future sleep500() {
  return new Future.delayed(const Duration(milliseconds: 500), () => "500");
}

class MockRequest {
  Uri uri;
  MockResponse response = new MockResponse();
  MockRequest.fromParamString(String params) {
    uri = Uri.parse("http://www.test.com/?${params}");
  }
}

class MockResponse {
  String data;
  write(String data) {
    this.data = data;
  }
  close() {}
}

String handleRequestWithResponse(MockRequest request) {
  handleRequest(request);
  return request.response.data;
}

void main() {
  test('TestReportAndGetSession', () {
    FRESH_MILLIS = 750;
    expect(handleRequestWithResponse(
            new MockRequest.fromParamString("r=a&p=b,c")),
        equals("OK"));
    expect(handleRequestWithResponse(
            new MockRequest.fromParamString("r=a&p=b,c")),
        equals("OK"));
    expect(handleRequestWithResponse(
            new MockRequest.fromParamString("g=1")),
        equals("[{\"r\":\"a\",\"p\":\"b,c\"}]"));

    sleep500().then((e){
      expect(handleRequestWithResponse(
              new MockRequest.fromParamString("r=d&p=e,f")),
          equals("OK"));
      expect(handleRequestWithResponse(
              new MockRequest.fromParamString("g=2")),
          equals("[{\"r\":\"a\",\"p\":\"b,c\"},{\"r\":\"d\",\"p\":\"e,f\"}]"));
      sleep500().then((e) {
        expect(handleRequestWithResponse(
                new MockRequest.fromParamString("g=2")),
          equals("[{\"r\":\"d\",\"p\":\"e,f\"}]"));   
      });
    });
  });
}