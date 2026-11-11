#!/usr/bin/env bash
# Validates the manifests of every environment against the Kubernetes API
# schemas with kubeconform (https://github.com/yannh/kubeconform).
#
#   bash scripts/validate-manifests.sh
set -euo pipefail
cd "$(dirname "$0")/.."

# Schemas of custom resources (Argo CD, Argo Rollouts) come from the
# community catalogue of CRD schemas.
validate() {
  kubeconform -strict -summary \
    -schema-location default \
    -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
    "$@"
}

for environment in dev staging production; do
  echo "== $environment"
  bash scripts/render-manifests.sh "$environment" | validate -
done
