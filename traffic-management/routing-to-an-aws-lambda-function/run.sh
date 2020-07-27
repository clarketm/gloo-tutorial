#!/usr/bin/env bash

set -e

##############################################################################################################################
# Setup
##############################################################################################################################

minikube start --memory=4096 --cpus=2
kubectl config use-context minikube
glooctl install gateway

# NOTE: run tunnel to access Gloo locally.
minikube tunnel -c &

##############################################################################################################################
# Expose Lambda Function via Gloo Gateway
##############################################################################################################################

#Apply the secret to access AWS Lambda
kubectl -n gloo-system apply -f secret.yaml

#Verify the secret was created:
kubectl -n gloo-system get secret lambda

#Expected output:
#NAME    TYPE    DATA AGE
#lambda  Opaque  2    10s

#We will use the AWS keys stored in the secret to access AWS and create an upstream named lambda that represents a collection of
#AWS Lambda functions found in the region us-east-1 on the account associated with the AWS keys.
glooctl create upstream aws --name lambda --aws-secret-name lambda --aws-region us-east-1

#Expected output:
#+----------+------------+---------+----------------------------+
#| UPSTREAM |  TYPE      | STATUS  |          DETAILS           |
#+----------+------------+---------+----------------------------+
#| lambda   | AWS Lambda | Pending | region: us-east-1          |
#|          |            |         | secret: gloo-system.lambda |
#+----------+------------+---------+----------------------------+

#The initial STATUS of the lambda upstream will be Pending. After a few seconds it should change to Accepted. Gloo will also detect all
#the AWS Lambda functions available in the region and AWS account. Let’s verify that by retrieving the upstream with glooctl:
glooctl get upstream lambda

#Expected output:
#+----------+------------+----------+----------------------------+
#| UPSTREAM |  TYPE      | STATUS   |          DETAILS           |
#+----------+------------+----------+----------------------------+
#| lambda   | AWS Lambda | Accepted | region: us-east-1          |
#|          |            |          | secret: gloo-system.lambda |
#|          |            |          | functions:                 |
#|          |            |          | - contact                  |
#|          |            |          | - contact-form             |
#
#........  output truncated .........
#
#|          |            |          | - uppercase
#+----------+------------+----------+----------------------------+

#Even though the upstream has been created, Gloo will not route traffic to it until we add some routing rules on a virtualservice.
#Let’s now use glooctl to create a route rule for this upstream to match a request sent to the path /uppercase, and use the --aws-function-name
#flag to specify that the uppercase function should be invoked.
glooctl add route --name lambda --dest-name lambda --aws-function-name uppercase --path-exact /uppercase

#Expected output:
#+-----------------+--------------+---------+------+---------+-----------------+-------------------------------+
#| VIRTUAL SERVICE | DISPLAY NAME | DOMAINS | SSL  | STATUS  | LISTENERPLUGINS |            ROUTES             |
#+-----------------+--------------+---------+------+---------+-----------------+-------------------------------+
#| lambda          |              | *       | none | Pending |                 | /uppercase ->                 |
#|                 |              |         |      |         |                 | gloo-system.lambda (upstream) |
#+-----------------+--------------+---------+------+---------+-----------------+-------------------------------+

#The initial STATUS of the lambda virtual service will be Pending. After a few seconds it should change to Accepted. Let’s verify that by
#retrieving the virtualservice with glooctl.
glooctl get virtualservice lambda

#Expected output:
#+-----------------+--------------+---------+------+----------+-----------------+-------------------------------+
#| VIRTUAL SERVICE | DISPLAY NAME | DOMAINS | SSL  | STATUS   | LISTENERPLUGINS |            ROUTES             |
#+-----------------+--------------+---------+------+----------+-----------------+-------------------------------+
#| lambda          |              | *       | none | Accepted |                 | /uppercase ->                 |
#|                 |              |         |      |          |                 | gloo-system.lambda (upstream) |
#+-----------------+--------------+---------+------+----------+-----------------+-------------------------------+

#At this point we have a virtualservice with a routing rule sending traffic on the path /uppercase to the upstream lambda and invoking the uppercase function.
#Let’s test the route rule by retrieving the url of the Gloo gateway, and sending a web request to the /uppercase path of the url using curl.
#As part of the request, we will include a data payload of "solo.io". This should return a json result of the data payload in all uppercase letters,
#e.g. "SOLO,IO". You can experiment with other data payloads to verify the route rule functionality.
curl --header "Content-Type: application/octet-stream" --header "Content-Type: Accept: application/octet-stream" --data "\"solo.io\"" $(glooctl proxy url)/uppercase

#Expected output:
#"SOLO.IO"

#Excellent! We have created an upstream to an AWS Lambda functions set, added a virtualservice, and added a route rule to handle requests for a specific function.

##############################################################################################################################
# Cleanup (optional)
##############################################################################################################################

#The following steps will remove the virtualservice, upstream and secret from the environment.

#First, we will remove the route:
#glooctl remove route --name lambda

#Second, we will remove the virtual service:
#glooctl delete virtualservice lambda

#Third, we will remove the upstream:
#glooctl delete upstream lambda

#Fourth, we will remove the secret:
#kubectl -n gloo-system delete secret lambda
