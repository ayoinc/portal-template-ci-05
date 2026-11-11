#!/usr/bin/env bash
# Applies the manifests to the cluster of the current kubectl context with
# the given image and waits until the new version is running.
#
#   bash scripts/deploy.sh <image> [dev|staging|production]
set -euo pipefail
cd "$(dirname "$0")/.."

image="${1:?Usage: bash scripts/deploy.sh <image>}"
name='sample-orders-service'
environment="${2:-dev}"
case "$environment" in
  dev | staging | production) ;;
  *)
    echo "Unknown environment '$environment': use dev, staging or production." >&2
    exit 1
    ;;
esac
manifests="k8s/overlays/$environment"
namespace="orders-$environment"

# The pods read their connection strings from this Secret, which is not kept
# in the repository.
if ! kubectl --namespace "$namespace" get secret "$name-secrets" > /dev/null 2>&1; then
  echo "Secret $name-secrets is missing in namespace $namespace. Create it first, see docs/index.md." >&2
  exit 1
fi

# A throwaway kustomization on top of the manifests replaces the image.
overlay="$(mktemp -d .deploy.XXXXXX)"
trap 'rm -rf "$overlay"' EXIT
cat > "$overlay/kustomization.yaml" << YAML
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../$manifests
images:
  - name: ghcr.io/example-org/sample-orders-service
    newName: ${image%:*}
    newTag: ${image##*:}
YAML

kubectl apply --kustomize "$overlay"

kubectl --namespace "$namespace" rollout status "deployment/$name" --timeout=300s
