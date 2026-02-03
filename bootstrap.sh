#! /usr/bin/env bash
set -e

echo ">>> Creating flux-system namespace..."
kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f -

echo ">>> Applying critical secrets..."
for secret in secrets/flux-system-secret.yaml secrets/sops-age-secret.yaml secrets/dockerhub-secret.yaml; do
    if [ -f "$secret" ]; then
        sops -d "$secret" | kubectl apply -f -
    else
        echo "Warning: $secret not found, skipping."
    fi
done

echo ">>> Applying Flux components and configuration..."
kubectl apply -f flux-system/

echo ">>> Reconciling Flux..."
flux reconcile kustomization flux-system -n flux-system --with-source

echo ">>> Bootstrap complete!"