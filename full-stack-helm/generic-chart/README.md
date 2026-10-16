# generic-chart

One shared Helm chart for every service. **A service doesn't write any templates.** It writes one values file and installs this chart with it:

```bash
helm upgrade --install my-app oci://<registry>/helm-charts/generic-chart --version 0.2.0 \
  -n my-namespace -f my-app-values.yaml
```

The chart is published once to a registry (ECR, Docker Hub or S3) with a version. Services pin that version, so a chart change only reaches a service when the service upgrades on purpose.

> Gateway setup (GatewayClass, Gateway, EnvoyProxy) is **not** in this chart. It's in [`../platform-gateway`](../platform-gateway) and installed once per cluster. Services only add routes to it.

---

## Contents

1. [What changed compared to `corrections`](#1-what-changed-compared-to-corrections)
2. [The one naming rule](#2-the-one-naming-rule)
3. [Try it](#3-try-it)
4. [Writing a values file](#4-writing-a-values-file)
5. [Mistakes the chart catches for you](#5-mistakes-the-chart-catches-for-you)
6. [Publishing a new chart version](#6-publishing-a-new-chart-version)
7. [Good to know](#7-good-to-know)
8. [Changing the chart](#8-changing-the-chart)

---

## 1. What changed compared to `corrections`

### In short

The `corrections` branch could run **one container per app, Deployments only**, with one ConfigMap, one Secret and one route per release. This branch keeps the same idea (*one chart, configured by values*) but removes those limits, adds safety checks, and documents everything.

### Before → after

| Topic | `corrections` | Now |
|---|---|---|
| **Workload types** | Deployment only | Deployment, **StatefulSet** (with a disk per pod), **DaemonSet** |
| **Containers per app** | 1 | **Any number.** Main app + sidecars. |
| **Image** | `image: { repository, tag }` per app | `image: "repo:tag"` as one string. Set it **once for the release**, and every container without its own image uses it. |
| **Ports** | One `port` per app | A `ports` list per container. The Service exposes all of them automatically. |
| **Autoscaling** | — | `hpa` per app (CPU and/or memory) |
| **Jobs** | One `job` + one `hooks.preInstall`, each a separate template | `jobs` map: **any number**. Add `hook: pre-install` to make one run before the app starts. |
| **CronJobs** | One `cronjob` | `cronJobs` map: any number |
| **Tests** | — | `tests` map: pods run by `helm test` |
| **ConfigMap** | One, env vars only | `configMaps` map: as **env vars or mounted files** (e.g. nginx.conf) |
| **Secret** | One, values via `--set` | `secrets` map, plus `externalSecrets` (synced from AWS Secrets Manager / Vault) |
| **Storage** | — | `persistentVolumeClaims` map (shared disk), plus `persistence` on StatefulSets |
| **Routing** | One `httpRoute`, one rate limit, one CORS policy | `httpRoutes`, `backendTrafficPolicies`, `securityPolicies` as maps. Policies point at routes by key. Any Envoy Gateway setting works. |
| **Ingress** | One host | `ingresses` map, many hosts |
| **ServiceAccount** | Pods used the namespace `default` | `serviceAccount` with IRSA annotations. API token **not** mounted by default. |
| **Security** | — | `defaults.podSecurityContext` / `securityContext` for every pod, overridable per app or container |
| **Scheduling** | — | `nodeSelector`, `tolerations`, `affinity`, `imagePullSecrets` for every pod, overridable per app |
| **Names** | Always `<name>-<key>` | Same, but the key **`default`** gets no suffix. See [section 2](#2-the-one-naming-rule). |
| **Pod restarts on config change** | Every pod restarted when any config changed | Only the pods that **use** that ConfigMap/Secret restart |
| **Typos in values** | Silently ignored | **Install fails** with the exact path (see [section 5](#5-mistakes-the-chart-catches-for-you)) |
| **Broken references** (route → missing app, etc.) | Rendered a broken object | **Install fails** with a clear message |
| **Docs** | None | This README, plus a commented example for every key in [`values.yaml`](values.yaml) |

### How the chart's files changed

```
corrections                              now
templates/deployments.yaml        →      templates/app.yaml            ← the ONLY file that renders.
templates/services.yaml                                                    It includes the files below,
templates/job.yaml                                                         one line each.
templates/pre-install-hook.yaml          templates/_helpers.tpl        ← all shared helper functions
templates/cronjob.yaml                   templates/_workloads.tpl      ← one file per resource kind
templates/configmap.yaml                 templates/_services.tpl          (files starting with "_" only
templates/secret.yaml                    templates/_hpas.tpl              hold definitions; app.yaml
templates/httproute.yaml                 templates/_jobs.tpl              pulls them in)
...                                      ... 16 files in total
                                         values.schema.json            ← new: rejects typos
```

The pod (containers, env, volumes, security) is defined **once** in `_helpers.tpl`, and apps, jobs, cron jobs and tests all use it. Before, jobs couldn't read the Secret because they had their own, smaller copy.

### Other changes on this branch

- **Examples:** `examples/our-app-values.yaml` (frontend + backend + Mongo in one release) is split into [`backend-values.yaml`](../examples/backend-values.yaml) and [`frontend-values.yaml`](../examples/frontend-values.yaml), one release per service. [`demo-values.yaml`](../examples/demo-values.yaml) shows every feature.
- **App code:** `app/backend/server.js` now reads the Mongo host from `MONGO_HOST`. It was hardcoded to `mongodb`, which didn't match the chart's Service name, so the backend couldn't reach Mongo.

### If you have a release from `corrections`

The values format is different, so old values files must be rewritten. The chart rejects old keys like `configMap:`, `secret:` and `job:`.

| Old | New |
|---|---|
| `configMap: { enabled, data }` | `configMaps: { default: { enabled, data } }` |
| `secret: { create, data }` | `secrets: { default: { enabled, data } }` |
| `envFromConfigMap: true` / `envFromSecret: true` | on the container: `envFromConfigMaps: [default]` / `envFromSecrets: [default]` |
| `apps.x.image: { repository: r, tag: t }` + `port: 80` | `apps.x.containers: [{ name: x, image: "r:t", ports: [{ name: http, containerPort: 80 }] }]` |
| `job:` / `hooks.preInstall:` / `cronjob:` | `jobs.<name>:` (with `hook:` for the pre-install one) / `cronJobs.<name>:` |
| `httpRoute: { parentName, backends }` | `httpRoutes.default: { parentRefs, rules: [{ matches, backendRefs }] }` |
| `backendTrafficPolicy` / `securityPolicy` | `backendTrafficPolicies.default` / `securityPolicies.default` |

Watch out for these:

- **Renaming an app key replaces the Deployment.** For example, `app` → `default` deletes the old Deployment and creates a new one. Keep the old keys if you want an in-place upgrade.
- **The ConfigMap and Secret get new names**, e.g. `fullstack-config` → `fullstack`. Update any `envValueFrom` that uses the old names.
- **An image without a tag** now pulls `:latest`. It no longer falls back to the chart version. Always write the tag.

---

## 2. The one naming rule

Everything in values is a **list of named entries** (a map). The entry's name, its *key*, becomes part of the resource name:

```
fullnameOverride: shop

apps:
  default:   →  Deployment "shop"          ← the key "default" adds nothing
  worker:    →  Deployment "shop-worker"   ← any other key is added with "-"
```

- **Always set `fullnameOverride` to your application name.**
- The rule is the same for every map: `apps`, `jobs`, `cronJobs`, `configMaps`, `secrets`, `httpRoutes`, and so on.
- A Service has the same name as its app.

**Inside values, you point at things by key, never by full name:**

```yaml
envFromSecrets: [default]                       # → Secret "shop"
volumes: [{ name: conf, configMap: nginx }]     # → ConfigMap "shop-nginx"
backendRefs: [{ service: default, port: 80 }]   # → Service "shop"
targetHttpRoutes: [default]                     # → HTTPRoute "shop"
```

If a key doesn't exist or isn't enabled, the install stops and tells you which one.

---

## 3. Try it

```bash
# Once per cluster: the shared Gateway
helm upgrade --install platform-gateway ./platform-gateway -n platform-gateway --create-namespace

# Per service
helm upgrade --install backend ./generic-chart -n fullstack --create-namespace \
  -f examples/backend-values.yaml --set secrets.default.data.MONGO_PASSWORD='<password>'
helm upgrade --install frontend ./generic-chart -n fullstack -f examples/frontend-values.yaml

# Run the test pods
helm test backend -n fullstack

# See exactly what would be created, without installing
helm template backend ./generic-chart -f examples/backend-values.yaml \
  --set secrets.default.data.MONGO_PASSWORD=x | less
```

The examples use the ECR images. On minikube, add `--set image=full-stack-backend:1.0` (or `full-stack-frontend:1.0`).

| Example | Shows |
|---|---|
| [`backend-values.yaml`](../examples/backend-values.yaml) | API with autoscaling. MongoDB as a StatefulSet with its own disk. ConfigMap + Secret, plus a commented ExternalSecret alternative. ServiceAccount, non-root security, a test pod, and an `/api` route with rate limit and CORS. |
| [`frontend-values.yaml`](../examples/frontend-values.yaml) | nginx frontend, a `/` route with security headers, rate limit, a test pod. |
| [`demo-values.yaml`](../examples/demo-values.yaml) | Everything. One image run as several apps with different commands (queue worker with autoscaling, scheduler, disk writer). Redis as a StatefulSet with a metrics **sidecar**. ConfigMap as env and as a mounted file. Jobs, a pre-install migration, a CronJob, a test, metrics scraping and routing. |

---

## 4. Writing a values file

Every key, with a commented example, is in [`values.yaml`](values.yaml). Copy what you need. Here's what each block does.

### Release-wide settings

```yaml
fullnameOverride: shop            # your application name: base of every resource name
image: 1234.dkr.ecr.../shop:1.4.2 # used by every container that doesn't set its own image
imagePullPolicy: IfNotPresent

serviceAccount:
  create: true                    # pods run as ServiceAccount "shop"
  annotations:                    # e.g. give pods an AWS role (IRSA)
    eks.amazonaws.com/role-arn: arn:aws:iam::<account>:role/shop

defaults:                         # applied to EVERY pod; an app can override any of these
  podSecurityContext: { runAsNonRoot: true, runAsUser: 1000 }
  securityContext: { allowPrivilegeEscalation: false, capabilities: { drop: [ALL] } }
  nodeSelector: {}
  tolerations: []
  affinity: {}
  imagePullSecrets: []
```

If an app sets one of the `defaults` keys itself, its value **replaces** the default. The two aren't merged.

### Apps (things that keep running)

```yaml
apps:
  default:                        # → Deployment "shop"
    enabled: true
    kind: Deployment              # or StatefulSet / DaemonSet
    replicas: 2
    containers:
      - name: web                 # no image → uses the release-wide image
        ports: [{ name: http, containerPort: 8080 }]
        envFromConfigMaps: [default]
        envFromSecrets: [default]
        probes:
          readinessProbe: { httpGet: { path: /health, port: http } }
        resources: { requests: { cpu: 100m, memory: 128Mi } }
    service: { enabled: true }    # → Service "shop", exposing every container port
    hpa:                          # → autoscaler; it then owns the replica count
      enabled: true
      minReplicas: 2
      maxReplicas: 6
      targetCPUUtilizationPercentage: 70

  worker:                         # → Deployment "shop-worker": same image, different command
    enabled: true
    containers:
      - name: worker
        command: ["php", "artisan", "queue:work"]
        envFromSecrets: [default]
```

| Want to… | Use |
|---|---|
| run a sidecar | add a second entry to `containers` |
| keep data per pod (databases) | `kind: StatefulSet` + `persistence: { size: 1Gi, mountPath: /data }` |
| mount a config file | `configMaps.<key>` + `volumes: [{ name: x, configMap: <key> }]` + `volumeMounts` on the container |
| share one disk | `persistentVolumeClaims.<key>` + `volumes: [{ name: x, pvc: <key> }]` |
| autoscale | `hpa` (needs metrics-server and `resources.requests`). Not for DaemonSets. |
| set env vars | `env: { KEY: value }`, or `envValueFrom` for a single key from a Secret/ConfigMap |

### Config and secrets

```yaml
configMaps:
  default:                        # → ConfigMap "shop": use as env vars
    enabled: true
    data: { APP_ENV: production }
  nginx:                          # → ConfigMap "shop-nginx": use as a file
    enabled: true
    data:
      default.conf: |
        server { listen 80; }

secrets:
  default:                        # → Secret "shop"
    enabled: true
    data: {}                      # NEVER commit values: --set secrets.default.data.DB_PASSWORD=...

externalSecrets:                  # OR sync from a secret manager (needs External Secrets Operator)
  default:
    enabled: true
    secretStoreRef: { name: aws-secrets-manager }
    dataFrom: [{ extract: { key: prod/shop } }]
```

A key can be in `secrets` **or** `externalSecrets`, not both, because both would create the same Secret.

### Jobs, CronJobs, tests

They use the same `containers` / `volumes` / `defaults` fields as apps.

```yaml
jobs:
  migrate:                        # → Job "shop-migrate"
    enabled: true
    hook: pre-install,pre-upgrade # runs BEFORE the app starts; the install stops if it fails
    containers:
      - name: migrate
        command: ["php", "artisan", "migrate", "--force"]
        envFromSecrets: [default]

cronJobs:
  report:                         # → CronJob "shop-report"
    enabled: true
    schedule: "0 6 * * *"
    containers:
      - name: report
        command: ["php", "artisan", "report:daily"]

tests:
  health:                         # → Pod "shop-test-health", run by `helm test`
    enabled: true
    containers:
      - name: check
        image: busybox:1.36
        command: ["wget", "-qO-", "http://shop/health"]
```

### Routing (Envoy Gateway)

```yaml
httpRoutes:
  default:                        # → HTTPRoute "shop"
    enabled: true
    parentRefs: [{ name: platform-gateway, namespace: platform-gateway }]
    hostnames: [shop.example.com]
    rules:
      - matches: [{ path: { type: PathPrefix, value: / } }]
        backendRefs: [{ service: default, port: 8080 }]   # service = an app key

backendTrafficPolicies:           # timeouts, rate limits, retries...
  default:
    enabled: true
    targetHttpRoutes: [default]
    rateLimit: { type: Local, local: { rules: [{ limit: { requests: 100, unit: Minute } }] } }

securityPolicies:                 # CORS, JWT, basic auth...
  default:
    enabled: true
    targetHttpRoutes: [default]
    cors: { allowOrigins: ["https://shop.example.com"] }
```

- **Policies:** apart from `enabled` and `targetHttpRoutes`, everything is passed to Envoy Gateway unchanged. Any Envoy Gateway option works without changing the chart.
- **No Gateway API in the cluster:** use `ingresses` instead (same idea: `rules` → `paths` → `service` key).

### Metrics

```yaml
serviceMonitor:
  enabled: true
  portName: metrics               # scrapes every Service port with this name
  additionalLabels: { release: kube-prometheus-stack }
```

---

## 5. Mistakes the chart catches for you

You'll see these errors on `helm install`, `helm upgrade`, `helm template` or `helm lint`, before anything reaches the cluster.

**Typos and wrong types**, caught by [`values.schema.json`](values.schema.json):

```
- at '/apps/worker/containers/0': additional properties 'envFromSecret' not allowed   ← typo
- at '/apps/worker/replicas': got string, want integer                               ← wrong type
- at '': additional properties 'secret' not allowed                                   ← old key from corrections
```

**Broken references and missing pieces**, caught by the templates:

```
httpRoutes.default.rules[0].backendRefs[0]: service "nope" must be an enabled apps.<key> with service.enabled: true
backendTrafficPolicies.default.targetHttpRoutes: route "api" must be an enabled httpRoutes.<key>
jobs.migrate.containers[0].envFromSecrets: "defualt" must be an enabled secrets or externalSecrets.<key>
apps.redis.containers[0].image is required (or set the release-wide image)
apps.worker.hpa: a DaemonSet can't be autoscaled (one pod per node)
```

Envoy Gateway policy settings are passed through unchanged, so the chart doesn't check them. The cluster rejects invalid ones when the release is applied.

---

## 6. Publishing a new chart version

1. Change the chart.
2. Bump `version` in [`Chart.yaml`](Chart.yaml).
3. Package and push:

```bash
helm lint generic-chart
helm package generic-chart                       # → generic-chart-0.2.0.tgz
```

**ECR:**

```bash
aws ecr create-repository --repository-name helm-charts/generic-chart --region us-west-1   # first time only
aws ecr get-login-password --region us-west-1 | \
  helm registry login --username AWS --password-stdin 200268988035.dkr.ecr.us-west-1.amazonaws.com
helm push generic-chart-0.2.0.tgz oci://200268988035.dkr.ecr.us-west-1.amazonaws.com/helm-charts
```

**Docker Hub:**

```bash
helm registry login registry-1.docker.io -u <user>
helm push generic-chart-0.2.0.tgz oci://registry-1.docker.io/<user>
```

**S3** (with the [helm-s3](https://github.com/hypnoglow/helm-s3) plugin):

```bash
helm plugin install https://github.com/hypnoglow/helm-s3.git
helm s3 init s3://<bucket>/charts                # first time only
helm repo add central s3://<bucket>/charts
helm s3 push generic-chart-0.2.0.tgz central
# services then install: central/generic-chart --version 0.2.0
```

---

## 7. Good to know

- **The HPA owns the replica count.** When `hpa` is on, `replicas` is ignored, so upgrades don't fight the autoscaler.
- **Pre-install jobs pull config forward.** A `pre-install` job runs before anything else exists. If you have one, the chart creates the ConfigMaps, Secrets and ServiceAccount first, so the job can read them. As a side effect, `helm uninstall` leaves those behind. Delete them with:
  ```bash
  kubectl delete cm,secret,sa,externalsecret -l app.kubernetes.io/instance=<release>
  ```
- **Adding a pre-install job to a release that's already installed** can make that one upgrade delete the ConfigMaps/Secrets. Reinstall instead. New installs are fine.
- **Plain jobs (no `hook`) run again on upgrade.** They're cleaned up 10 minutes after finishing and recreated by the next upgrade, so make them safe to run twice.
- **Don't autoscale a plain database.** A second Redis or Mongo pod is a separate, empty database. Keep `replicas: 1`, or use a real clustered setup.
- **ExternalSecrets don't restart pods when they change.** The chart can't see their values. Use a reloader if you need that.
- **`envValueFrom` uses real names**, e.g. `secretKeyRef: { name: shop, key: X }`, not keys.

---

## 8. Changing the chart

```
generic-chart/
  values.yaml          defaults + a commented example for every key
  values.schema.json   what keys/types are allowed
  templates/
    app.yaml           the only rendered file: one include line per _*.tpl
    _helpers.tpl       shared functions: names, the pod template, job spec, policy spec
    _<kind>.tpl        one file per resource kind (_workloads.tpl, _services.tpl, _hpas.tpl, ...)
```

| To add… | Do this |
|---|---|
| a new values key | add it to `values.yaml` (with a comment) **and** `values.schema.json`, or the schema will reject it |
| a new pod/container field | add it once in `podTemplate` / `container` in `_helpers.tpl`, and apps, jobs, cron jobs and tests all get it |
| a new resource kind | create `_<kind>.tpl` with `define "generic-chart.<kind>"`, then add one `include` line to `app.yaml` |

Check your change against all three examples:

```bash
for f in backend frontend demo; do
  helm lint generic-chart -f examples/$f-values.yaml \
    --set secrets.default.data.MONGO_PASSWORD=x --set secrets.default.data.DB_PASSWORD=x
done
```

Then bump `version` in `Chart.yaml` and publish (see [section 6](#6-publishing-a-new-chart-version)).
