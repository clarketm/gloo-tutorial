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
# Pet Store Application v1 Setup
##############################################################################################################################

#We will start by deploying v1 of the Pet Store app to the Kubernetes cluster using the YAML file located in the home directory.
kubectl apply -f petstore-v1.yaml

#Expected output:
#deployment.apps/petstore-v1 created
#service/petstore-v1 created

#Now let's verify the petstore-v1 pod is running and the petstore-v1 service has been created:
kubectl -n default get pods

#Expected output:
#NAME                   READY  STATUS   RESTARTS  AGE
#petstore-v1-####-####  1/1    Running  0         30s

#If the pod is not yet running, rerun the get pods command until it is.
#Let's verify that the petstore-v1 service has been created as well.
#Note that the service does not have an external IP address. It is only accessible within the Kubernetes cluster.
kubectl -n default get svc petstore-v1

#Expected output:
#NAME         TYPE       CLUSTER-IP   EXTERNAL-IP  PORT(S)   AGE
#petstore-v1  ClusterIP  10.XX.XX.XX  <none>       8080/TCP  1m

#Enable Gloo’s Function Discovery (fds) service.
kubectl label namespace default discovery.solo.io/function_discovery=enabled

#The Gloo discovery services should have already created an upstream for the petstore-v1 service, and the STATUS should be Accepted.
#Let’s verify this by using the glooctl command line tool:
glooctl get upstreams default-petstore-v1-8080

#Expected output:
#+--------------------------+------------+----------+------------------------+
#|          UPSTREAM        |    TYPE    |  STATUS  |          DETAILS       |
#+--------------------------+------------+----------+------------------------+
#| default-petstore-v1-8080 | Kubernetes | Accepted | svc name : petstore-v1 |

#The application endpoints were discovered by Gloo’s Function Discovery (fds) service. This was possible because the petstore application implements
#OpenAPI (specifically, discovering a Swagger JSON document at petstore-svc/swagger.json).

#Even though the upstream has been created, Gloo will not route traffic to it until we add some routing rules on a virtualservice.
#Let’s now use glooctl to create a basic route on the path /petstore for this upstream with the --prefix-rewrite flag to rewrite the path on
#incoming requests to the path /api/pets.
glooctl add route \
  --name petstore \
  --path-exact /petstore \
  --dest-name default-petstore-v1-8080 \
  --prefix-rewrite /api/pets

#Expected output:
#+-----------------+--------------+---------+------+---------+-----------------+------------------------------+
#| VIRTUAL SERVICE | DISPLAY NAME | DOMAINS | SSL  | STATUS  | LISTENERPLUGINS |             ROUTES           |
#+-----------------+--------------+---------+------+---------+-----------------+------------------------------+
#| petstore        |              | *       | none | Pending |                 | /petstore -> gloo-system.    |
#|                 |              |         |      |         |                 | .default-petstore-v1-8080    |
#+-----------------+--------------+---------+------+---------+-----------------+------------------------------+

#The initial STATUS of the petstore virtual service will be Pending. After a few seconds it should change to Accepted.
#Let’s verify that by retrieving the virtualservice with glooctl.
glooctl get virtualservice petstore

#At this point we have a virtualservice called petstore with a routing rule sending traffic on the path /all-pets to the upstream petstore at a path of /api/pets.
#Let’s test the route rule by retrieving the url of the Gloo gateway, and sending a web request to the /all-pets path of the url using curl:
curl $(glooctl proxy url)/petstore

#Expected output:
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
