#!/usr/bin/env bash

set -e

##############################################################################################################################
# Setup
##############################################################################################################################

minikube start --memory=4096 --cpus=2
kubectl config use-context minikube
glooctl install gateway

#Create an Upstream for the external application postman-echo.com:
glooctl -n gloo-system create upstream static --name echo --static-hosts postman-echo.com:80

#Create a route and corresponding virtual service for the postman-echo application:
glooctl add route --name echo --path-prefix / --dest-name echo

#Make sure the virtual service and route are Accepted:
#glooctl get upstream echo

# NOTE: run tunnel to access Gloo locally.
minikube tunnel -c &

##############################################################################################################################
# Section 1 - Response Code
##############################################################################################################################
#In the first section, we will demonstrate transforming the http response code based posted data.

#Test the postman-echo upstream. You should see a 200 response with the contents of data-transformed.json:
curl -s -o /dev/null -w "%{http_code}" -H "Content-Type: application/json" $(glooctl proxy url)/post -d @data-transformed.json # 200
curl -H "Content-Type: application/json" $(glooctl proxy url)/post -d @data-transformed.json | jq
#{
#  "args": {},
#  "data": {
#    "error": {
#      "message": "This is an error"
#    }
#  },
#  "files": {},
#  "form": {},
#  "headers": {
#    "x-forwarded-proto": "http",
#    "x-forwarded-port": "80",
#    "host": "192.168.64.8",
#    "x-amzn-trace-id": "Root=1-5f1772ff-0bf3b23043b42940ab76ac60",
#    "content-length": "50",
#    "user-agent": "curl/7.64.1",
#    "accept": "*/*",
#    "content-type": "application/json",
#    "x-request-id": "911cc18a-2f53-4a8e-88c2-113be79c9030",
#    "x-envoy-expected-rq-timeout-ms": "15000"
#  },
#  "json": {
#    "error": {
#      "message": "This is an error"
#    }
#  },
#  "url": "http://192.168.64.8/post"
#}

#To change the response code, edit the virtual service by adding the `options`:
#https://docs.solo.io/gloo/1.0.0/gloo_routing/virtual_services/routes/routing_features/transformations/
kubectl -n gloo-system edit virtualservice echo
# PASTE in `options` from: virtualservice-options-1.yaml

#Test the transformed response code. You should now see a 400 response code:
curl -s -o /dev/null -w "%{http_code}" -H "Content-Type: application/json" $(glooctl proxy url)/post -d @data-transformed.json     # 400
curl -s -o /dev/null -w "%{http_code}" -H "Content-Type: application/json" $(glooctl proxy url)/post -d @data-not-transformed.json # 200

##############################################################################################################################
# Section 2 - Extract Query Parameters
##############################################################################################################################
#In the second section, we will demonstrate how to extract query parameters.

#Test the baseline response from an http query. Note there are no foobar headers:
curl -s "$(glooctl proxy url)/get?foo=foo-value&bar=bar-value" | jq
#{
#  "args": {
#    "foo": "foo-value",
#    "bar": "bar-value"
#  },
#  "headers": {
#    "x-forwarded-proto": "http",
#    "x-forwarded-port": "80",
#    "host": "192.168.64.8",
#    "x-amzn-trace-id": "Root=1-5f178128-9420ae8894c7e7c871ce5ae8",
#    "content-length": "0",
#    "user-agent": "curl/7.64.1",
#    "accept": "*/*",
#    "x-request-id": "609c1c89-cd9b-4d2f-8c49-79fd44856dcd",
#    "x-envoy-expected-rq-timeout-ms": "15000"
#  },
#  "url": "http://192.168.64.8/get?foo=foo-value&bar=bar-value"
#}

#Add the `requestTransformation` to the echo virtual service:
#https://docs.solo.io/gloo/latest/guides/traffic_management/request_processing/transformations/
kubectl -n gloo-system edit virtualservice echo
# PASTE in `options` from: virtualservice-options-2.yaml

#Now test the configuration by issuing a query. Note that there are now foobar headers:
curl -s "$(glooctl proxy url)/get?foo=foo-value&bar=bar-value" | jq
#{
#  "args": {
#    "foo": "foo-value",
#    "bar": "bar-value"
#  },
#  "headers": {
#    "x-forwarded-proto": "http",
#    "x-forwarded-port": "80",
#    "host": "192.168.64.8",
#    "x-amzn-trace-id": "Root=1-5f178532-fe507c8c89cc0fb0ff7cf890",
#    "content-length": "0",
#    "user-agent": "curl/7.64.1",
#    "accept": "*/*",
#    "x-request-id": "93af0e7d-266c-4bef-b6d6-be184388cefd",
#    "foo": "foo-value",
#    "bar": "bar-value",
#    "x-envoy-expected-rq-timeout-ms": "15000"
#  },
#  "url": "http://192.168.64.8/get?foo=foo-value&bar=bar-value"
#}

##############################################################################################################################
# Section 3 - Modify Request Path
##############################################################################################################################
#In the third section, we will demonstrate how to conditionally update the request path.

#Test the baseline response. Note that the url is a GET:
curl -s -H "boo: far" $(glooctl proxy url)/get | jq
#{
#  "args": {},
#  "headers": {
#    "x-forwarded-proto": "http",
#    "x-forwarded-port": "80",
#    "host": "192.168.64.8",
#    "x-amzn-trace-id": "Root=1-5f1785d4-736ee55d607ba2f1a249ef23",
#    "content-length": "0",
#    "user-agent": "curl/7.64.1",
#    "accept": "*/*",
#    "boo": "far",
#    "x-request-id": "eaa7dead-ea3c-4c17-9d17-85e699f9fca7",
#    "x-envoy-expected-rq-timeout-ms": "15000"
#  },
#  "url": "http://192.168.64.8/get"
#}

#Add the new `:path` and `:method` `headers` to the `requestTransformation`:
kubectl -n gloo-system edit virtualservice echo
# PASTE in `options` from: virtualservice-options-3.yaml

#Test the new transform. Note that the url is now a POST:
curl -s -H "boo: far" $(glooctl proxy url)/get | jq
#{
#  "args": {},
#  "data": {},
#  "files": {},
#  "form": {},
#  "headers": {
#    "x-forwarded-proto": "http",
#    "x-forwarded-port": "80",
#    "host": "192.168.64.8",
#    "x-amzn-trace-id": "Root=1-5f17873c-3fdecae22de19be8790cf20d",
#    "content-length": "0",
#    "user-agent": "curl/7.64.1",
#    "accept": "*/*",
#    "boo": "far",
#    "x-request-id": "5f523e92-bc60-4c7f-a40d-fb925be3f5c5",
#    "x-envoy-expected-rq-timeout-ms": "15000"
#  },
#  "json": null,
#  "url": "http://192.168.64.8/post"
#}

#Now test the transform without the header. Note that the transform is not triggered.
curl -s $(glooctl proxy url)/get | jq
#{
#  "args": {},
#  "headers": {
#    "x-forwarded-proto": "http",
#    "x-forwarded-port": "80",
#    "host": "192.168.64.8",
#    "x-amzn-trace-id": "Root=1-5f178d08-4b7438de43b0095edcc09c1c",
#    "content-length": "0",
#    "user-agent": "curl/7.64.1",
#    "accept": "*/*",
#    "x-request-id": "cea7b230-b506-4020-ad4b-dc398663725d",
#    "x-envoy-expected-rq-timeout-ms": "15000"
#  },
#  "url": "http://192.168.64.8/get"
#}

##############################################################################################################################
# Section 4 - Extract Headers
##############################################################################################################################
#In the fourth section, we will demonstrate how to extract headers and add them to the JSON request body.

#Test the baseline using the following data. Note that the only data payload is "foo: bar".
curl -H "Content-Type: application/json" -H "root: root-val" -H "nested: nested-val" $(glooctl proxy url)/post -d @data-payload.json | jq
#{
#  "args": {},
#  "data": {
#    "payload": {
#      "foo": "bar"
#    }
#  },
#  "files": {},
#  "form": {},
#  "headers": {
#    "x-forwarded-proto": "http",
#    "x-forwarded-port": "80",
#    "host": "192.168.64.8",
#    "x-amzn-trace-id": "Root=1-5f178d81-bb4606146015ac5aad55f03b",
#    "content-length": "35",
#    "user-agent": "curl/7.64.1",
#    "accept": "*/*",
#    "content-type": "application/json",
#    "root": "root-val",
#    "nested": "nested-val",
#    "x-request-id": "947771e6-c2fa-4124-8b08-ba18c8a7c255",
#    "x-envoy-expected-rq-timeout-ms": "15000"
#  },
#  "json": {
#    "payload": {
#      "foo": "bar"
#    }
#  },
#  "url": "http://192.168.64.8/post"
#}

#To merge the headers into the body add the `root:` and `payload.nested:` `extractors` and `merge_extractors_to_body` tag to the `requestTransformation`
#https://docs.solo.io/gloo/1.0.0/gloo_routing/virtual_services/routes/routing_features/transformations/
kubectl -n gloo-system edit virtualservice echo
# PASTE in `options` from: virtualservice-options-4.yaml

#Now test updated transform. Note that the header has been added to the body.
curl -H "Content-Type: application/json" -H "root: root-val" -H "nested: nested-val" $(glooctl proxy url)/post -d @data-payload.json | jq
#{
#  "args": {},
#  "data": {
#    "payload": {
#      "foo": "bar",
#      "nested": "nested-val"
#    },
#    "root": "root-val"
#  },
#  "files": {},
#  "form": {},
#  "headers": {
#    "x-forwarded-proto": "http",
#    "x-forwarded-port": "80",
#    "host": "192.168.64.8",
#    "x-amzn-trace-id": "Root=1-5f178e54-b2af82a8e22b5c6b325a4eb2",
#    "content-length": "65",
#    "user-agent": "curl/7.64.1",
#    "accept": "*/*",
#    "content-type": "application/json",
#    "root": "root-val",
#    "nested": "nested-val",
#    "x-request-id": "4346d4bb-31bc-4642-a598-38ff51268be4",
#    "x-envoy-expected-rq-timeout-ms": "15000"
#  },
#  "json": {
#    "payload": {
#      "foo": "bar",
#      "nested": "nested-val"
#    },
#    "root": "root-val"
#  },
#  "url": "http://192.168.64.8/post"
#}

##############################################################################################################################
# Section 5 - Custom Request Logging
##############################################################################################################################
#In the fifth section, we will demonstrate how to add custom attributes to the access logs.

#First, enable access logging by adding the `options` to the Gateway configuration for the `accessLoggingService`:
kubectl -n gloo-system edit gateway
# PASTE in `spec` from: virtualservice-options-5.1.yaml

#Now make a request:
curl -s $(glooctl proxy url)/get | jq
#{
#  "args": {},
#  "headers": {
#    "x-forwarded-proto": "http",
#    "x-forwarded-port": "80",
#    "host": "192.168.64.8",
#    "x-amzn-trace-id": "Root=1-5f1790c9-058b30d69461ea30612797a4",
#    "content-length": "35",
#    "user-agent": "curl/7.64.1",
#    "accept": "*/*",
#    "x-request-id": "3731dee8-36f7-494c-bec1-b9110e5a32e8",
#    "x-envoy-expected-rq-timeout-ms": "15000"
#  },
#  "url": "http://192.168.64.8/get"
#}

#And check the logs:
kubectl logs -n gloo-system deployment/gateway-proxy | grep '^{' | jq
#{
#  "clientDuration": "242",
#  "httpMethod": "GET",
#  "upstreamName": "echo_gloo-system",
#  "responseCode": "200",
#  "systemTime": "2020-07-22T01:05:09.162Z",
#  "targetDuration": "242",
#  "path": "/get",
#  "protocol": "HTTP/1.1",
#  "requestId": "65d2365b-4d6b-4386-8c44-b8352fd21540"
#}

#Lets add the `pod_name` and the `endpoint_url` to the logging configuration under `jsonFormat` in the `accessLoggingService`:
kubectl -n gloo-system edit gateway
# PASTE in `spec` from: virtualservice-options-5.2.yaml

#Now add a transformation to the virtual service by adding `dynamicMetadataValues` to the `responseTransformation`:
kubectl -n gloo-system edit virtualservice echo
# PASTE in `spec` from: virtualservice-options-5.3.yaml

#Make another request:
curl -s $(glooctl proxy url)/get | jq
#{
#  "args": {},
#  "headers": {
#    "x-forwarded-proto": "http",
#    "x-forwarded-port": "80",
#    "host": "192.168.64.8",
#    "x-amzn-trace-id": "Root=1-5f179165-e8dbd9da3c4fecf247c3676b",
#    "content-length": "0",
#    "user-agent": "curl/7.64.1",
#    "accept": "*/*",
#    "x-request-id": "bc01ed40-dbe8-4fb5-b866-f556fec52dad",
#    "x-envoy-expected-rq-timeout-ms": "15000"
#  },
#  "url": "http://192.168.64.8/get"
#}

#And check the logs. Now you should see entries for pod_name and entrypoint_url:
kubectl logs -n gloo-system deployment/gateway-proxy | grep '^{' | jq
#{
#  "pod_name": "\"gateway-proxy-5dc75fd9d7-ztfxl\"",
#  "clientDuration": "181",
#  "httpMethod": "GET",
#  "upstreamName": "echo_gloo-system",
#  "responseCode": "200",
#  "systemTime": "2020-07-22T01:07:49.104Z",
#  "targetDuration": "180",
#  "path": "/get",
#  "requestId": "bc01ed40-dbe8-4fb5-b866-f556fec52dad",
#  "protocol": "HTTP/1.1",
#  "endpoint_url": "\"http://192.168.64.8/get\""
#}
