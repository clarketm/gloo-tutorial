#!/usr/bin/env bash

set -e

##############################################################################################################################
# Setup
##############################################################################################################################

minikube start --memory=4096 --cpus=2
kubectl config use-context minikube

#Install the Gloo, Consul, Vault, and sample Pet Store application:
docker-compose up -d

#You can view the logs by:
tail -f docker-compose.log

#Make sure the docker images are up and running:
docker ps

##############################################################################################################################
# Consul Integration
##############################################################################################################################

#Now that we have the containers up and running, we have to provide Gloo with a gateway configuration.
#We will do that be writing the configuration in gw-proxy.yaml to the Key/Value store in Consul using curl.
curl --request PUT --data-binary @./data/gateways/gloo-system/gw-proxy.yaml http://127.0.0.1:8500/v1/kv/gloo/gateway.solo.io/v1/Gateway/gloo-system
#true

#Next we are going to create the petstore service on Consul.
#First, we need to get the IP address of the petstore container. The command below retrieves the IP address and
#then creates a JSON file with information about the Pet Store application. The JSON file will be submitted to Consul to create the service:
PETSTORE_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' integration_petstore_1)
cat >petstore-service.json <<EOF
{
  "ID": "petstore1",
  "Name": "petstore",
  "Address": "${PETSTORE_IP}",
  "Port": 8080
}
EOF

#Now that we have the JSON file for the Pet Store application, let’s register the petstore service with Consul using curl:
curl -v \
  -XPUT \
  --data @petstore-service.json \
  "http://127.0.0.1:8500/v1/agent/service/register"

#The petstore service can be used as an Upstream destination by a Virtual Service definition on Gloo. Let’s now use
#glooctl to create a basic route for this upstream with the --prefix-rewrite flag to rewrite the path on incoming requests
#to match the path our petstore application expects. The --use-consul flag indicates to Gloo that it will be using Consul to
#store this configuration and not Kubernetes.
glooctl add route \
  --path-exact /all-pets \
  --dest-name petstore \
  --prefix-rewrite /api/pets \
  --use-consul

#Confirm the virtualservice is Accepted:
glooctl get vs --use-consul

#We should now be able to send a request to the Gloo proxy on the path /all-pets and retrieve a result from the Pet Store
#application on the path /api/pets. Let’s use curl to send a request:
curl http://localhost:8080/all-pets

#The response should look like the JSON payload shown below.
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
