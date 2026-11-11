# sample-orders-service

Order processing microservice of the sample team: it's the "orders" domain

Node.js microservice with Kubernetes manifests and a pipeline.

## Getting started

```bash
docker build -t sample-orders-service:local .
docker run --rm -p 8080:8080 sample-orders-service:local
```

```bash
curl http://localhost:8080/
curl http://localhost:8080/health
```

## Commands

- `docker build --target test .` runs the unit tests inside the image build
- `bash scripts/render-manifests.sh` prints the Kubernetes manifests
- `bash scripts/validate-manifests.sh` validates them with kubeconform
- `bash scripts/check-policies.sh` checks them against the policies in `policy/`
- `bash scripts/kind-test.sh sample-orders-service:local` deploys the image to a throwaway kind cluster
- `bash scripts/deploy.sh <image>` applies the manifests to the current kubectl context

## Documentation

`docs/index.md` describes the service, the manifests, the pipeline and how to
enable deployment; it is published as TechDocs in the developer portal.

## Owner

group:default/platform-team
