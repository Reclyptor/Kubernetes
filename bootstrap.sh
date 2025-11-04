#! /usr/bin/env bash

kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f -

sops -d secrets/flux-system-secret.yaml | kubectl apply -f -
sops -d secrets/sops-age-secret.yaml | kubectl apply -f -
sops -d secrets/dockerhub-secret.yaml | kubectl apply -f -

kubectl apply -f flux-system/gotk-components.yaml
kubectl apply -f flux-system/gotk-sync.yaml

kubectl -n flux-system patch kustomization flux-system --type merge -p '
spec:
  decryption:
    provider: sops
    secretRef: { name: sops-age }
'

flux reconcile source git flux-system -n flux-system
flux reconcile kustomization flux-system -n flux-system --with-source
