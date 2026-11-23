#!/bin/bash
# Видалення кластера після роботи:  bash tools/gcp_down.sh
gcloud compute instances delete parcs-master parcs-worker-1 parcs-worker-2 parcs-worker-3 parcs-worker-4 \
  --zone=europe-central2-a --quiet
