#!/bin/bash
# Створення кластера PARCS у Google Cloud (Cloud Shell):  bash tools/gcp_up.sh
# master + 4 workers, Container-Optimized OS, n1-standard-1, europe-central2-a
set -e
ZONE=europe-central2-a
MASTER_IP=10.186.0.10
IMG="--image-family=cos-stable --image-project=cos-cloud --machine-type=n1-standard-1"
# COS має власний iptables-фаєрвол, що блокує вхідні з'єднання -> відкриваємо його у startup-скрипті
START="iptables -I INPUT -j ACCEPT; docker run -d --name parcs --restart=always --net=host"

gcloud config set compute/zone $ZONE
gcloud services enable compute.googleapis.com

gcloud compute firewall-rules describe allow-all >/dev/null 2>&1 || \
gcloud compute firewall-rules create allow-all --direction=INGRESS --priority=1000 \
  --network=default --action=ALLOW --rules=all --source-ranges=0.0.0.0/0

gcloud compute instances create parcs-master $IMG --private-network-ip=$MASTER_IP \
  --metadata=startup-script="$START -e PARCS_ARGS=master hummer12007/parcs-node"

gcloud compute instances create parcs-worker-1 parcs-worker-2 parcs-worker-3 parcs-worker-4 $IMG \
  --metadata=startup-script="$START -e PARCS_ARGS=\"worker $MASTER_IP\" hummer12007/parcs-node"

gcloud compute instances list
