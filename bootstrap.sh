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

echo ">>> Applying Flux components..."
kubectl apply -f flux-system/gotk-components.yaml

echo ">>> Waiting for Flux CRDs to be established..."
kubectl wait --for condition=established --timeout=60s crd/gitrepositories.source.toolkit.fluxcd.io
kubectl wait --for condition=established --timeout=60s crd/kustomizations.kustomize.toolkit.fluxcd.io

echo ">>> Applying Flux sync configuration..."
kubectl apply -f flux-system/gotk-sync.yaml

echo ">>> Reconciling Flux..."
flux reconcile kustomization flux-system -n flux-system --with-source

echo ">>> Bootstrap complete!"