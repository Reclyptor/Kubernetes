#! /usr/bin/env bash
set -e

echo ">>> Creating flux-system namespace..."
kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f -

echo ">>> Applying secrets..."
shopt -s nullglob
for secret in secrets/*.yaml; do
    sops -d "$secret" | kubectl apply -f -
done
shopt -u nullglob

echo ">>> Applying Flux components and configuration..."
kubectl apply -f flux-system/

echo ">>> Reconciling Flux..."
flux reconcile kustomization flux-system -n flux-system --with-source

echo ">>> Bootstrap complete!"