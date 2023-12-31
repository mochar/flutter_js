import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;

import 'package:flutter_js/javascript_runtime.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/*
 * Based on bits and pieces from different OSS sources
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// ignore: non_constant_identifier_names
var _XHR_DEBUG = false;

setXhrDebug(bool value) => _XHR_DEBUG = value;

const HTTP_GET = "get";
const HTTP_POST = "post";
const HTTP_PATCH = "patch";
const HTTP_DELETE = "delete";
const HTTP_PUT = "put";
const HTTP_HEAD = "head";

enum HttpMethod { put, get, post, delete, patch, head }

RegExp regexpHeader = RegExp("^([\\w-])+:(?!\\s*\$).+\$");

class XhrPendingCall {
  int? idRequest;
  String? method;
  String? url;
  Map<String, String> headers;
  String? body;

  XhrPendingCall({
    required this.idRequest,
    required this.method,
    required this.url,
    required this.headers,
    required this.body,
  });
}

const XHR_PENDING_CALLS_KEY = "xhrPendingCalls";

http.Client? httpClient;

xhrSetHttpClient(http.Client client) {
  httpClient = client;
}

extension JavascriptRuntimeXhrExtension on JavascriptRuntime {
  List<dynamic>? getPendingXhrCalls() {
    return dartContext[XHR_PENDING_CALLS_KEY];
  }

  bool hasPendingXhrCalls() => getPendingXhrCalls()!.length > 0;
  void clearXhrPendingCalls() {
    dartContext[XHR_PENDING_CALLS_KEY] = [];
  }

  JavascriptRuntime enableXhr() {
    httpClient = httpClient ?? http.Client();
    dartContext[XHR_PENDING_CALLS_KEY] = [];

    // var cli = HttpClient();
    // cli.findProxy = (uri) {
    //   return "PROXY 192.168.31.114:7890";
    // };
    // cli.findProxy = HttpClient.findProxyFromEnvironment;

    // httpClient = IOClient(cli);
    Timer.periodic(Duration(milliseconds: 40), (timer) {
      // exits if there is no pending call to remote
      if (!hasPendingXhrCalls()) return;

      // collect the pending calls into a local variable making copies
      List<dynamic> pendingCalls = List<dynamic>.from(getPendingXhrCalls()!);
      // clear the global pending calls list
      clearXhrPendingCalls();

      // for each pending call, calls the remote http service
      pendingCalls.forEach((element) async {
        XhrPendingCall pendingCall = element as XhrPendingCall;
        HttpMethod eMethod = HttpMethod.values.firstWhere((e) =>
            e.toString().toLowerCase() ==
            ("HttpMethod.${pendingCall.method}".toLowerCase()));
        late http.Response response;
        switch (eMethod) {
          case HttpMethod.head:
            response = await httpClient!.head(
              Uri.parse(pendingCall.url!),
              headers: pendingCall.headers,
            );
            break;
          case HttpMethod.get:
            response = await httpClient!.get(
              Uri.parse(pendingCall.url!),
              headers: pendingCall.headers,
            );
            break;
          case HttpMethod.post:
            response = await httpClient!.post(
              Uri.parse(pendingCall.url!),
              body: (pendingCall.body is String)
                  ? pendingCall.body
                  : jsonEncode(pendingCall.body),
              headers: pendingCall.headers,
            );
            break;
          case HttpMethod.put:
            response = await httpClient!.put(
              Uri.parse(pendingCall.url!),
              body: (pendingCall.body is String)
                  ? pendingCall.body
                  : jsonEncode(pendingCall.body),
              headers: pendingCall.headers,
            );
            break;
          case HttpMethod.patch:
            response = await httpClient!.patch(
              Uri.parse(pendingCall.url!),
              body: (pendingCall.body is String)
                  ? pendingCall.body
                  : jsonEncode(pendingCall.body),
              headers: pendingCall.headers,
            );
            break;
          case HttpMethod.delete:
            response = await httpClient!.delete(
              Uri.parse(pendingCall.url!),
              headers: pendingCall.headers,
            );
            break;
        }
        // assuming request was successfully executed
        String responseText = utf8.decode(response.bodyBytes);
        // try {
        //   responseText = jsonEncode(json.decode(responseText));
        // } on Exception {}
        final xhrResult = XmlHttpRequestResponse(
          responseText: responseText,
          responseInfo:
              XhtmlHttpResponseInfo(statusCode: response.statusCode, 
                statusText: response.reasonPhrase),
        );

        response.headers.forEach((key, value) {
          xhrResult.responseInfo?.addResponseHeaders(key, value);
        });

        final responseInfo = jsonEncode(xhrResult.responseInfo);
        //final responseText = xhrResult.responseText; //.replaceAll("\\n", "\\\n");
        final error = xhrResult.error;
        // send back to the javascript environment the
        // response for the http pending callback
        developer.log('''
        Got response for ${response.request?.url}
          - id: ${pendingCall.idRequest}
          - status code: ${response.statusCode}
          - error: $error
        ''', name: 'xhr');
        final r = this.evaluate(
          "globalThis.xhrRequests[${pendingCall.idRequest}].callback($responseInfo, ${jsonEncode(responseText)}, $error);",
        );
        developer.log(r.stringResult, name: 'xhr callback');
      });
    });

    this.onMessage('SendNative', (arguments) {
      try {
        String? method = arguments[0];
        String? url = arguments[1];
        dynamic headersList = arguments[2];
        String? body = arguments[3];
        int? idRequest = arguments[4];

        Map<String, String> headers = {};
        headersList.forEach((header) {
          // final headerMatch = regexpHeader.allMatches(value).first;
          // String? headerName = headerMatch.group(0);
          // String? headerValue = headerMatch.group(1);
          // if (headerName != null) {
          //   headers[headerName] = headerValue ?? '';
          // }
          String headerKey = header[0];
          headers[headerKey] = header[1];
        });
        (dartContext[XHR_PENDING_CALLS_KEY] as List<dynamic>).add(
          XhrPendingCall(
            idRequest: idRequest,
            method: method,
            url: url,
            headers: headers,
            body: body,
          ),
        );
      } on Error catch (e) {
        if (_XHR_DEBUG) print('ERROR calling sendNative on Dart: >>>> $e');
      } on Exception catch (e) {
        if (_XHR_DEBUG) print('Exception calling sendNative on Dart: >>>> $e');
      }
    });
    return this;
  }
}

class XhtmlHttpResponseInfo {
  final int? statusCode;
  final String? statusText;
  final List<List<String>> responseHeaders = [];

  XhtmlHttpResponseInfo({
    this.statusCode,
    this.statusText,
  });

  void addResponseHeaders(String name, String value) {
    responseHeaders.add([name, value]);
  }

  Map<String, Object?> toJson() {
    return {
      "statusCode": statusCode,
      "statusText": statusText,
      "responseHeaders": jsonEncode(responseHeaders)
    };
  }
}

class XmlHttpRequestResponse {
  final String? responseText;
  final String? error; // should be timeout in case of timeout
  final XhtmlHttpResponseInfo? responseInfo;

  XmlHttpRequestResponse({this.responseText, this.responseInfo, this.error});

  Map<String, Object?> toJson() {
    return {
      'responseText': responseText,
      'responseInfo': responseInfo!.toJson(),
      'error': error
    };
  }
}
