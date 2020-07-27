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
# Expose External Service via Gloo Gateway
##############################################################################################################################

#We will start by using the Gloo command line utility glooctl to create a static upstream pointing to the OpenWeather host at api.openweathermap.org.
glooctl create upstream static --name weather --static-hosts api.openweathermap.org

#Expected output:
#+----------+--------+---------+-----------------------------+
#| UPSTREAM |  TYPE  | STATUS  |       DETAILS               |
#+----------+--------+---------+-----------------------------+
#| weather  | Static | Pending | hosts:                      |
#|          |        |         | - api.openweathermap.org:80 |
#+----------+--------+---------+-----------------------------+

#The initial STATUS of the weather upstream will be Pending. After a few seconds it should change to Accepted.
#Let’s verify that by retrieving the upstream with glooctl.
glooctl get upstream weather

#Expected output:
#+----------+--------+----------+-----------------------------+
#| UPSTREAM |  TYPE  | STATUS   |       DETAILS               |
#+----------+--------+----------+-----------------------------+
#| weather  | Static | Accepted | hosts:                      |
#|          |        |          | - api.openweathermap.org:80 |
#+----------+--------+----------+-----------------------------+

#Even though the upstream has been created, Gloo will not route traffic to it until we add some routing rules on a virtualservice.
#Let’s now use glooctl to create a basic route for this upstream to match a request sent to the path /boston-weather, and use the
#--prefix-rewrite flag to rewrite the path on incoming requests to the endpoint /data/2.5/weather, adding the city of Boston as a query and the API key.
glooctl add route --name weather --path-exact /boston-weather --dest-name weather --prefix-rewrite "/data/2.5/weather?q=Boston&APPID=5b8354119b9b297f9d84de9d819adee2"

#Expected output:
#+-----------------+--------------+---------+------+---------+-----------------+--------------------------------+
#| VIRTUAL SERVICE | DISPLAY NAME | DOMAINS | SSL  | STATUS  | LISTENERPLUGINS |            ROUTES              |
#+-----------------+--------------+---------+------+---------+-----------------+--------------------------------+
#| weather         |              | *       | none | Pending |                 | /boston-weather ->             |
#|                 |              |         |      |         |                 | gloo-system.weather (upstream) |
#+-----------------+--------------+---------+------+---------+-----------------+--------------------------------+

#The initial STATUS of the weather virtual service will be Pending. After a few seconds it should change to Accepted.
#Let’s verify that by retrieving the virtualservice with glooctl.
glooctl get virtualservice

#Expected output:
#+-----------------+--------------+---------+------+----------+-----------------+--------------------------------+
#| VIRTUAL SERVICE | DISPLAY NAME | DOMAINS | SSL  | STATUS   | LISTENERPLUGINS |            ROUTES              |
#+-----------------+--------------+---------+------+----------+-----------------+--------------------------------+
#| weather         |              | *       | none | Accepted |                 | /boston-weather ->             |
#|                 |              |         |      |          |                 | gloo-system.weather (upstream) |
#+-----------------+--------------+---------+------+----------+-----------------+--------------------------------+

#At this point we have a virtualservice with a routing rule sending traffic on the path /boston-weather to the upstream weather at a path of /data/2.5/weather.
#Let’s test the route rule by retrieving the url of the Gloo gateway, and sending a web request to the /boston-weather path of the url using curl.
#This should return a json result describing the Boston weather, which we will pipe to jq to make it more readable:
curl $(glooctl proxy url)/boston-weather | jq

#Expected output:
#{
#    "coord": {
#        "lon": -71.06,
#        "lat": 42.36
#    },
#    "weather": [...],
#    "base": "stations",
#
#    ... output truncated ...
#
#}

#Excellent! We have created an upstream to an external service, added a virtualservice, and added a route rule to handle requests.

##############################################################################################################################
# Cleanup (optional)
##############################################################################################################################

#The following steps will remove the virtualservice and upstream from the environment.

#First, we will remove the route:
#glooctl remove route --name weather

#Second, we will remove the virtualservice:
#glooctl delete virtualservice weather

#Third, we will remove the upstream:
#glooctl delete upstream weather
