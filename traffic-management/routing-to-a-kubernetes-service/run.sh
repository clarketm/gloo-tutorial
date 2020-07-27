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
# Routing to Kubernetes Service
##############################################################################################################################

#We will start by deploying the Pet Store app to the Kubernetes cluster using the YAML file located in the home directory.
kubectl apply -f petstore.yaml

#Expected output:
#deployment.apps/petstore created
#service/petstore created

#Now let's verify the petstore pod is running and the petstore service has been created:
kubectl -n default get pods

#Expected output:
#NAME                READY  STATUS   RESTARTS  AGE
#petstore-####-####  1/1    Running  0         30s

#If the pod is not yet running, rerun the get pods command until it is.
#Let's verify that the petstore service has been created as well.
kubectl -n default get svc petstore

#Note that the service does not have an external IP address. It is only accessible within the Kubernetes cluster.
#Expected output:
#NAME      TYPE       CLUSTER-IP   EXTERNAL-IP  PORT(S)   AGE
#petstore  ClusterIP  10.XX.XX.XX  <none>       8080/TCP  1m

#Enable Gloo’s Function Discovery (fds) service.
kubectl label namespace default discovery.solo.io/function_discovery=enabled

#The Gloo discovery services should have already created an upstream for the petstore service, and the STATUS should be Accepted.
#Let’s verify this by using the glooctl command line tool:
glooctl get upstream default-petstore-8080

#Please wait until Gloo discovers the REST functions in the expected output:
#+-----------------------+------------+----------+-------------------------+
#|       UPSTREAM        |    TYPE    |  STATUS  |         DETAILS         |
#+-----------------------+------------+----------+-------------------------+
#| default-petstore-8080 | Kubernetes | Accepted | svc name:      petstore |
#|                       |            |          | svc namespace: default  |
#|                       |            |          | port:          8080     |
#|                       |            |          | REST service:           |
#|                       |            |          | functions:              |
#|                       |            |          | - addPet                |
#|                       |            |          | - deletePet             |
#|                       |            |          | - findPetById           |
#|                       |            |          | - findPets              |
#|                       |            |          |                         |
#+-----------------------+------------+----------+-------------------------+

#The application endpoints were discovered by Gloo’s Function Discovery (fds) service. This was possible because the petstore application
#implements OpenAPI (specifically, discovering a Swagger JSON document at petstore-svc/swagger.json).

#If we want to get more detail about the upstream that Gloo’s Discovery service created, we can specify the output as YAML and pipe it to more.
glooctl get upstream default-petstore-8080 --output yaml | more

#Even though the upstream has been created, Gloo will not route traffic to it until we add some routing rules on a virtualservice.
#Let’s now use glooctl to create a basic route for this upstream with the --prefix-rewrite flag to rewrite the path on incoming requests
#to match the paths our petstore application expects.
glooctl add route \
  --name petstore \
  --path-exact /all-pets \
  --dest-name default-petstore-8080 \
  --prefix-rewrite /api/pets

#Expected output:
#+-----------------+--------------+---------+------+---------+-----------------+---------------------------+
#| VIRTUAL SERVICE | DISPLAY NAME | DOMAINS | SSL  | STATUS  | LISTENERPLUGINS |          ROUTES           |
#+-----------------+--------------+---------+------+---------+-----------------+---------------------------+
#| petstore        |              | *       | none | Pending |                 | /all-pets -> gloo-system. |
#|                 |              |         |      |         |                 | .default-petstore-8080    |
#+-----------------+--------------+---------+------+---------+-----------------+---------------------------+

#The initial STATUS of the petstore virtual service will be Pending. After a few seconds it should change to Accepted.
#Let’s verify that by retrieving the virtualservice with glooctl.
glooctl get virtualservice petstore

#At this point we have a virtualservice with a routing rule sending traffic on the path /all-pets to the upstream petstore at a path of /api/pets.
#Let’s test the route rule by retrieving the url of the Gloo gateway, and sending a web request to the /all-pets path of the url using curl:
curl $(glooctl proxy url)/all-pets

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

#The petstore virtualservice can contain multiple route rules. Let's say we wanted to retrieve information about a specific pet using
#their Id and the function findPetById. We can create a new route offering that function on the path /findPetById.
glooctl add route \
  --name petstore \
  --path-prefix /findPetById \
  --dest-name default-petstore-8080 \
  --rest-function-name findPetById \
  --rest-parameters ':path=/findPetById/{id}'

#Expected output:
#+-----------------+--------------+---------+------+----------+-----------------+------------------------------+
#| VIRTUAL SERVICE | DISPLAY NAME | DOMAINS | SSL  |  STATUS  | LISTENERPLUGINS |          ROUTES              |
#+-----------------+--------------+---------+------+----------+-----------------+------------------------------+
#| petstore        |              | *       | none | Accepted |                 | /findPetById -> gloo-system. |
#|                 |              |         |      |          |                 | .default-petstore-8080       |
#|                 |              |         |      |          |                 | /all-pets -> gloo-system.    |
#|                 |              |         |      |          |                 | .default-petstore-8080       |
#+-----------------+--------------+---------+------+----------+-----------------+------------------------------+

#Let’s test the new route using curl and submitting a value of 1 for the pet Id:
curl $(glooctl proxy url)/findPetById/1

#Expected output:
#{
#  "id": 1,
#  "name": "Dog",
#  "status": "available"
#}

#Excellent! We have deployed an application, created an upstream and virtualservice, and added routes to handle requests.

##############################################################################################################################
# Cleanup (optional)
##############################################################################################################################

#The following steps will remove the virtualservice, upstream and Pet Store application from the environment.

#First, we will remove the virtualservice:
#glooctl delete virtualservice petstore

#Second, we will remove the upstream:
#glooctl delete upstream default-petstore-8080

#Finally, we will remove the Pet Store application:
#kubectl delete -f petstore.yaml
