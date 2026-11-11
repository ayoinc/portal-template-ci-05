# sample-orders-service

Order processing microservice of the sample team: it's the "orders" domain

## Overview

| Setting             | Value                                                                               |
| ------------------- | ----------------------------------------------------------------------------------- |
| Service             | `sample-orders-service`                                                                |
| Owner               | `group:default/platform-team`                                                               |
| Language            | Node.js 24 |
| Namespace           | `orders-dev`, `orders-staging`, `orders-production` |
| Environments        | dev, staging, production (kustomize overlays) |
| Workload            | `Deployment` (rolling update) |
| Cloud provider      | aws                                                        |
| Database            | postgresql                                                         |
| Message queue       | none                                                         |
| Monitoring          | prometheus-grafana                                                      |
| Repository          | <https://github.com/example-org/sample-orders-service> |

```d2
direction: right

push: Push to main {
  shape: oval
}

ci: CI {
  lint: "Lint\nHadolint, kubeconform"
  image: "Image\nunit tests, build, probes"
  lint -> image
}

registry: ghcr.io {
  shape: cylinder
}

cluster: Kubernetes {
  ingress: Ingress
  service: Service
  workload: "Deployment\nsample-orders-service"
  ingress -> service -> workload
}

push -> ci.lint
ci.image -> registry: publish
deploy: Deploy workflow
ci.image -> deploy: after success
deploy -> cluster: scripts/deploy.sh
registry -> cluster.workload: pull
```

## Project structure

```
sample-orders-service/
├── .github/workflows/
│   ├── ci.yaml                # Lint, unit tests, image build and publish
│   ├── deploy.yaml            # Deployment to the cluster (aws)
│   ├── integration.yaml       # Deployment to a throwaway kind cluster
│   ├── security.yaml          # Trivy scans
│   ├── policy.yaml            # Policy check of the manifests
│   └── code-quality.yaml      # SonarQube analysis
├── src/                       # The service (index.js, server.js)
├── test/                      # Unit tests (node --test)
├── package.json
├── package-lock.json
├── Dockerfile                 # Build, test and runtime stages
├── k8s/
│   ├── base/                  # Manifests shared by all environments
│   └── overlays/              # dev, staging, production
├── policy/                    # OPA policies for the manifests, with tests
├── scripts/
│   ├── render-manifests.sh    # Prints the manifests of an environment
│   ├── validate-manifests.sh  # kubeconform validation
│   ├── check-policies.sh      # conftest policy check
│   ├── kind-test.sh           # Deploys to a throwaway kind cluster
│   └── deploy.sh              # Applies the manifests with a given image
├── api-spec.yaml              # OpenAPI description of the endpoints
├── sonar-project.properties
├── catalog-info.yaml          # Backstage catalog entry
└── mkdocs.yml                 # TechDocs configuration
```

## The service

A starter service without dependencies outside the standard library. It listens on the port in `PORT` (default `8080`).

| Method | Path       | Response                                                            |
| ------ | ---------- | ------------------------------------------------------------------- |
| GET    | `/`        | `{ "service": "sample-orders-service", "environment": "..." }`         |
| GET    | `/health`  | `{ "status": "healthy" }`, used by the liveness and startup probes  |
| GET    | `/ready`   | `{ "status": "ready" }`, used by the readiness probe                |
| GET    | `/metrics` | `http_requests_total` in the Prometheus text format                 |
| other  | any        | `404` with `{ "error": "Not Found" }`                               |

`environment` is the value of the `ENVIRONMENT` variable, which the ConfigMap
sets; outside the cluster it is `local`. `api-spec.yaml` describes the
endpoints in OpenAPI 3.

The `Dockerfile` has a build stage, a `test` stage that runs the unit tests,
and a runtime stage that runs as the non-root user `10001`.

```bash
docker build --target test .                 # unit tests
docker build -t sample-orders-service:local .   # image
docker run --rm -p 8080:8080 sample-orders-service:local
```

## Kubernetes manifests

The manifests are a kustomize directory, `k8s/base/`:

| File                  | Resource                                                                         |
| --------------------- | -------------------------------------------------------------------------------- |
| `namespace.yaml`      | Namespace with the restricted Pod Security Standard enforced |
| `serviceaccount.yaml` | ServiceAccount without an API token                                              |
| `configmap.yaml`      | ConfigMap `sample-orders-service-config`, loaded as environment variables           |
| `workload.yaml`       | Deployment (rolling update): probes, resource limits, read-only root filesystem, non-root |
| `service.yaml`        | ClusterIP Service on port 80 |
| `ingress.yaml`        | Ingress for `sample-orders-service.example.com`                                     |
| `networkpolicy.yaml`  | Allows the HTTP port in; DNS, HTTPS and the configured dependencies out          |
| `hpa.yaml`            | HorizontalPodAutoscaler, 2 to 10 pods on CPU and memory                          |
| `pdb.yaml`            | PodDisruptionBudget, one pod unavailable at most                                 |

```bash
bash scripts/render-manifests.sh staging     # print the manifests
bash scripts/validate-manifests.sh   # kubeconform, every environment
```

Things to adapt before the first real deployment:

- **Host name.** Replace `sample-orders-service.example.com` in `k8s/base/ingress.yaml` and in the overlays.
- **Ingress class.** The Ingress uses the `alb` class of the AWS Load Balancer Controller and creates an internal Application Load Balancer.
- **Image pull.** Packages on ghcr.io are private by default. Make the package public or add an image pull secret to the ServiceAccount.

### Environments

`k8s/overlays/<environment>` adjusts the base for each environment:

| Environment | Namespace                                       | Host                                     |
| ----------- | ----------------------------------------------- | ---------------------------------------- |
| dev         | `orders-dev`        | `sample-orders-service-dev.example.com`     |
| staging     | `orders-staging`    | `sample-orders-service-staging.example.com` |
| production  | `orders-production` | `sample-orders-service.example.com`         |

Each overlay also sets `ENVIRONMENT` and the number of pods.

### Connection strings

The pods read `DATABASE_URL` from the Secret
`sample-orders-service-secrets`. The Secret is not kept in the repository; create
it in each namespace before the first deployment:

```bash
kubectl --namespace <namespace> create secret generic sample-orders-service-secrets \
  --from-literal=database-url='<connection string>'
```

The starter service does not open these connections yet. The NetworkPolicy
already allows the pods to reach the postgresql port.

## Observability

The service exposes `http_requests_total` on `/metrics`. The pods carry the
`prometheus.io/scrape`, `prometheus.io/port` and `prometheus.io/path`
annotations, which a Prometheus with annotation-based discovery uses to scrape them.

The pods are annotated for auto-instrumentation by the
[OpenTelemetry Operator](https://opentelemetry.io/docs/platforms/kubernetes/operator/automatic/).
With the operator and an `Instrumentation` resource in the cluster, traces are
exported without code changes; `OTEL_SERVICE_NAME` is set in the ConfigMap and
the NetworkPolicy allows OTLP traffic (ports 4317 and 4318). Without the
operator the annotation has no effect.

## Continuous integration

Every workflow runs on pushes and pull requests to `main`.

| Workflow           | What it does                                                                                    |
| ------------------ | ----------------------------------------------------------------------------------------------- |
| `ci.yaml`          | Hadolint, kubeconform, unit tests (`--target test`), image build, start and probe calls, publish |
| `integration.yaml` | Creates a kind cluster, deploys the image with the manifests of dev and calls the service |
| `security.yaml`    | Trivy reports: misconfigurations of manifests and Dockerfile, vulnerable dependencies, image     |
| `policy.yaml`      | conftest: unit tests of the policies, then the manifests of every environment against them      |
| `code-quality.yaml` | SonarQube analysis; skipped until the `SONAR_TOKEN` secret exists                              |

On pushes to `main`, `ci.yaml` publishes the image to the GitHub Container
Registry with the workflow's own token:

```
ghcr.io/example-org/sample-orders-service:latest
ghcr.io/example-org/sample-orders-service:sha-<commit>
```

The Trivy scans report and do not fail the build. In a public repository the
misconfiguration results also appear in the repository's Security tab.

### Policies

`policy/workload.rego` holds the rules: non-root pods, no privilege
escalation, read-only root filesystem, all capabilities dropped, CPU and
memory requests and limits, liveness and readiness probes, no host network,
no LoadBalancer Services. `policy/workload_test.rego` tests them.

```bash
conftest verify --policy policy    # unit tests of the policies
bash scripts/check-policies.sh     # the manifests against the policies
```

The namespace is labelled to enforce the restricted
[Pod Security Standard](https://kubernetes.io/docs/concepts/security/pod-security-standards/),
so Kubernetes itself rejects pods that break it.

### SonarQube

Set the repository secret `SONAR_TOKEN` to enable the analysis. For SonarQube
Server also set the repository variable `SONAR_HOST_URL`; without it the
results go to SonarQube Cloud. Project key and organisation are in
`sonar-project.properties`.

### Integration test

```bash
docker build -t sample-orders-service:local .
bash scripts/kind-test.sh sample-orders-service:local
```

The script needs Docker, kind, kubectl and curl. It creates the cluster
`sample-orders-service-test`, deploys with `scripts/deploy.sh`, calls every
endpoint through a port-forward and deletes the cluster.

## Deployment

`.github/workflows/deploy.yaml` runs after every successful CI run on `main`
and on demand (**Actions**, **Deploy**, **Run workflow**). It deploys the
image of that commit with `scripts/deploy.sh`: to `dev` after CI, or to the environment given when it is started by hand.

Until it is configured the workflow only reports that deployment is skipped.
To enable it, create an IAM role that trusts this repository through
[GitHub's OIDC provider](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
and may access the EKS cluster, then set these repository variables:

| Variable           | Value                          |
| ------------------ | ------------------------------ |
| `AWS_ROLE_ARN`     | ARN of the role to assume      |
| `AWS_REGION`       | Region of the cluster          |
| `EKS_CLUSTER_NAME` | Name of the EKS cluster        |

To deploy by hand, point kubectl at the cluster and run:

```bash
bash scripts/deploy.sh ghcr.io/example-org/sample-orders-service:sha-<commit> staging
```

## References

- [Kustomize](https://kubectl.docs.kubernetes.io/references/kustomize/)
- [kubeconform](https://github.com/yannh/kubeconform)
- [conftest](https://www.conftest.dev/)
