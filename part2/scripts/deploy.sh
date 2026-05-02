#!/bin/bash

CONFS="/home/vagrant/confs"

kubectl apply -f "${CONFS}/app1.yaml"
kubectl apply -f "${CONFS}/app2.yaml"
kubectl apply -f "${CONFS}/app3.yaml"
kubectl apply -f "${CONFS}/ingress.yaml"

echo ""
echo "==> Done! Test with:"
echo "    curl -H 'Host: app1.com' http://192.168.56.110"
echo "    curl -H 'Host: app2.com' http://192.168.56.110"
echo "    curl http://192.168.56.110"