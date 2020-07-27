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
# Load Balancing
##############################################################################################################################

#We will start by deploying the Pet Store app to the Kubernetes cluster using the YAML file located in the home directory.
kubectl -n default apply -f petstore.yaml

#Now scale the petstore to 2 pods. These pods will be the targets of Gloo load-balancing:
kubectl -n default scale deployment petstore --replicas=2

#Wait until the petstore pods are ready:
kubectl -n default get pods

#For each pod note the IP address save to a variable:
IP1=$(kubectl -n default get pod -o jsonpath='{.items[0].status.podIP}')
#172.18.0.8
IP2=$(kubectl -n default get pod -o jsonpath='{.items[1].status.podIP}')
#172.18.0.7

#Now create a static upstream using these 2 pod IPs:
glooctl create upstream static --name static-pet --static-hosts $IP1:8080,$IP2:8080

#Wait until the upstream is Accepted:
glooctl get upstream static-pet

#Now add a route and virtual service for the application:
glooctl add route \
  --name default \
  --path-prefix /api \
  --dest-name static-pet

#Wait until the route and virtual service are Accepted:
glooctl get virtualservice default

#You should be able to access the services:
curl $(glooctl proxy url)/api/pets
#[
#  {
#    "id": 1,
#    "name": "Dog",
#    "status": "available"
#  },
#  {
#    "id": 2,
#    "name": "Cat",
#    "status": "pending"
#  }
#]

#Now lets modify the load-balancing for the 3 endpoints by adding healthChecks and loadBalancerConfig:
kubectl -n gloo-system edit upstream static-pet
# PASTE in `options` from: upstream-spec-1.yaml

#You should be able to access the services through the new random load-balancing config:
curl $(glooctl proxy url)/api/pets
#[
#  {
#    "id": 1,
#    "name": "Dog",
#    "status": "available"
#  },
#  {
#    "id": 2,
#    "name": "Cat",
#    "status": "pending"
#  }
#]

#Now create a failing health check by setting path: /foo:
kubectl -n gloo-system edit upstream static-pet
# PASTE in `options` from: upstream-spec-2.yaml

#Retest a few times and you should see "no healthy upstream":
curl $(glooctl proxy url)/api/pets
#no healthy upstream

##############################################################################################################################
# Cleanup (optional)
##############################################################################################################################

#The following steps will remove the virtualservice, upstream and secret from the environment.

#First, we will remove the route:
#glooctl remove route --name default

#Second, we will remove the virtual service:
#glooctl delete virtualservice default

#Third, we will remove the upstream:
#glooctl delete upstream static-pet

#Fourth, we will remove the secret:
#kubectl -n default delete -f petstore.yaml
