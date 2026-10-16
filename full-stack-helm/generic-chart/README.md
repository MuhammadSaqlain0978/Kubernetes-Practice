# generic-chart

A reusable Helm chart for deploying **one service per release** using only a values file. A service can have any number of:

- long-running workloads (Deployment, StatefulSet, DaemonSet)
- one-off Jobs and Helm hook Jobs (e.g. a DB migration that must run before the app starts)
- CronJobs

The chart can also create the Services, ConfigMap, Secret, ServiceAccount, Ingress or Gateway API routing (Envoy Gateway), and ServiceMonitor around them.

Every workload, job and cron job is built from **one shared pod template**. So image, env, secrets, resources, security context and scheduling work the same way everywhere.

Gateway infrastructure (GatewayClass, Gateway, EnvoyProxy, ClientTrafficPolicy) is **not** in this chart. It lives in [`../platform-gateway`](../platform-gateway) and is installed once per cluster. This chart only attaches routes to it.

---

## Contents

- [Mental model](#mental-model)
- [Quick start](#quick-start)
- [Examples](#examples)
- [Values reference](#values-reference)
- [How it works](#how-it-works)
- [Validation](#validation)
- [Caveats](#caveats)
- [Upgrading from 0.1.x](#upgrading-from-01x)
- [Developing the chart](#developing-the-chart)

---

## Mental model

```
one service  =  one helm release  =  one values file
```

| Release `backend` (`examples/backend-values.yaml`) | Release `frontend` (`examples/frontend-values.yaml`) |
|---|---|
| `apps.api` → Deployment + Service `backend-api` | `apps.web` → Deployment + Service `frontend-web` |
| `apps.mongo` → StatefulSet + Service + PVC | |
| ConfigMap `backend-config`, Secret `backend-secret` | |
| ServiceAccount `backend` | ServiceAccount `frontend` |
| HTTPRoute `fullstack.local/api` | HTTPRoute `fullstack.local/` |

- **Inside a release, everything is one service.** Every pod in a release can read the same ConfigMap, Secret and ServiceAccount. Each pod chooses whether it actually reads them.
- **Between releases, nothing is shared.** The frontend can't see the backend's Secret.
- Both releases attach routes to the same platform Gateway and hostname. The Gateway sends `/api` to the backend and everything else to the frontend.

**Resource names** follow the pattern `<fullname>-<key>`:

- `fullname` is `fullnameOverride`. If that's not set, it's `<release>-<chart name>`.
- `key` is the entry name under `apps`, `jobs` or `cronJobs`.

The key also becomes the `app.kubernetes.io/component` label and the container name.

---

## Quick start

```bash
# 1. Once per cluster: Envoy Gateway + the shared Gateway
helm upgrade --install platform-gateway ./platform-gateway -n platform-gateway --create-namespace

# 2. One release per service
helm upgrade --install backend ./generic-chart -n fullstack --create-namespace \
  -f examples/backend-values.yaml \
  --set secret.data.MONGO_PASSWORD='<password>'

helm upgrade --install frontend ./generic-chart -n fullstack \
  -f examples/frontend-values.yaml
```

Check what will be applied before installing:

```bash
helm template backend ./generic-chart -f examples/backend-values.yaml \
  --set secret.data.MONGO_PASSWORD=x | less
```

---

## Examples

| File | What it shows |
|---|---|
| [`examples/backend-values.yaml`](../examples/backend-values.yaml) | API Deployment and MongoDB StatefulSet with a PVC. ConfigMap + Secret, ServiceAccount (with an IRSA annotation slot), non-root security defaults, a per-app override for Mongo, and an `/api` HTTPRoute with rate limit and CORS. |
| [`examples/frontend-values.yaml`](../examples/frontend-values.yaml) | Static nginx frontend with a root-compatible security context and a `/` HTTPRoute. |
| [`examples/demo-values.yaml`](../examples/demo-values.yaml) | Every feature in one release: 4 apps, a plain Job, a pre-install hook Job that reads the Secret, a CronJob, a ServiceMonitor and Gateway policies. |

The backend and frontend examples use the ECR images from [`commands.txt`](../commands.txt). On minikube, override them:

```bash
--set apps.api.image=full-stack-backend:1.0   # backend
--set apps.web.image=full-stack-frontend:1.0  # frontend
```

---

## Values reference

Every block is optional. A block you leave out renders nothing.

### Top level

| Key | Default | Description |
|---|---|---|
| `nameOverride` | `""` | Replaces the chart name in `<release>-<name>`. |
| `fullnameOverride` | `""` | Base name for every resource. Use it for short names, e.g. `backend` gives `backend-api`. |

### `configMap`: one per release

| Key | Default | Description |
|---|---|---|
| `configMap.enabled` | `false` | Renders `<fullname>-config`. |
| `configMap.data` | `{}` | `KEY: value`. Values are quoted as strings. |

Pods read it with `envFromConfigMap: true` (all keys) or with `envValueFrom` + `configMapKeyRef` (single keys).

### `secret`: one per release

| Key | Default | Description |
|---|---|---|
| `secret.create` | `false` | Renders `<fullname>-secret` from `secret.data`. Fails if `data` is empty. |
| `secret.data` | `{}` | **Never commit real values.** Pass them with `--set secret.data.KEY=...`. |
| `secret.existing` | `""` | Name of a Secret created outside the chart, e.g. by External Secrets, Sealed Secrets or Vault. `envFromSecret` then points to it. Can't be combined with `create`. |

### `serviceAccount`: one per release, used by every pod

| Key | Default | Description |
|---|---|---|
| `serviceAccount.create` | `false` | Creates a ServiceAccount named `name`, or `<fullname>` if `name` is empty. |
| `serviceAccount.name` | `""` | With `create: false`, the name of an existing SA to use. Empty means the namespace's `default` SA. |
| `serviceAccount.annotations` | `{}` | Cloud identity, e.g. `eks.amazonaws.com/role-arn` (IRSA) or `iam.gke.io/gcp-service-account`. |
| `serviceAccount.automountServiceAccountToken` | `false` | Set this on both the SA and every pod. Turn it on only if the app calls the Kubernetes API. |

### `defaults`: release-wide pod settings

Applied to **every** app, job and cron job. Any entry can set the same key itself, and its value **replaces** the default for that entry. There is no deep merge: an entry's `securityContext` replaces the whole default `securityContext`. Set `{}` or `[]` to opt an entry out of a default.

| Key | Lands in | Example |
|---|---|---|
| `podSecurityContext` | `spec.securityContext` | `{ runAsNonRoot: true, runAsUser: 1000, fsGroup: 1000, seccompProfile: { type: RuntimeDefault } }` |
| `securityContext` | `containers[].securityContext` | `{ allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: { drop: [ALL] } }` |
| `imagePullSecrets` | `spec.imagePullSecrets` | `[{ name: regcred }]` |
| `nodeSelector` | `spec.nodeSelector` | `{ kubernetes.io/arch: amd64 }` |
| `tolerations` | `spec.tolerations` | `[{ key: dedicated, value: batch, effect: NoSchedule }]` |
| `affinity` | `spec.affinity` | raw Kubernetes affinity object |

### Pod fields: shared by `apps.*`, `jobs.*` and `cronJobs.*`

| Key | Default | Description |
|---|---|---|
| `enabled` | — | Only enabled entries render. |
| `image` | **required** | One string: `repo:tag`, `registry/repo:tag` or `repo@sha256:...`. Used exactly as written. Always include a tag. |
| `imagePullPolicy` | `IfNotPresent` | `Always` / `IfNotPresent` / `Never`. |
| `command`, `args` | — | Lists of strings. |
| `env` | — | `NAME: value` plain values. |
| `envValueFrom` | — | `NAME: <valueFrom object>`, e.g. `{ secretKeyRef: { name: backend-secret, key: PASSWORD } }`. |
| `envFromConfigMap` | `false` | Inject all keys from the release ConfigMap. |
| `envFromSecret` | `false` | Inject all keys from the release Secret (or `secret.existing`). |
| `resources` | — | `{ requests: {...}, limits: {...} }`. |
| `annotations` | — | Pod annotations. |
| `podSecurityContext`, `securityContext`, `imagePullSecrets`, `nodeSelector`, `tolerations`, `affinity` | from `defaults` | Per-entry override. See [`defaults`](#defaults-release-wide-pod-settings). |

### `apps.<name>`: Deployment, StatefulSet or DaemonSet

All the pod fields above, plus:

| Key | Default | Description |
|---|---|---|
| `kind` | `Deployment` | `Deployment` \| `StatefulSet` \| `DaemonSet`. |
| `replicas` | k8s default (1) | Ignored for DaemonSet. |
| `port` | — | Container port. Also the Service `targetPort`. |
| `probes` | — | `readinessProbe` / `livenessProbe` / `startupProbe` as raw Kubernetes probe objects. |
| `persistence` | — | StatefulSet only. `{ size: 1Gi, mountPath: /data, storageClass: "", accessMode: ReadWriteOnce }`. `mountPath` is required. Each pod gets its own PVC (`data-<name>-0`, ...). |
| `service.enabled` | `false` | Creates Service `<fullname>-<name>`. Required for a StatefulSet, because it's the governing Service. |
| `service.type` | `ClusterIP` | `ClusterIP` / `NodePort` / `LoadBalancer`. |
| `service.port` | `port` | Service port. |
| `service.portName` | `http` | Port name. ServiceMonitor matches on it. |

### `jobs.<name>`: Job or Helm hook Job

All the pod fields above, plus:

| Key | Default | Description |
|---|---|---|
| `hook` | — | Makes it a Helm hook, e.g. `pre-install,pre-upgrade` or `post-install`. Leave it out for a plain Job. |
| `hookWeight` | `0` | Lower weights run first. |
| `hookDeletePolicy` | `before-hook-creation,hook-succeeded` | |
| `backoffLimit` | `2` | `0` is respected. |
| `restartPolicy` | `Never` | `Never` / `OnFailure`. |
| `activeDeadlineSeconds` | — | |
| `ttlSecondsAfterFinished` | `600` for plain jobs | See [Plain Jobs re-run on upgrade](#caveats). |

### `cronJobs.<name>`

All the pod fields above, plus `backoffLimit`, `restartPolicy`, `activeDeadlineSeconds` and `ttlSecondsAfterFinished` (as for jobs), and:

| Key | Default | Description |
|---|---|---|
| `schedule` | **required** | Cron expression. |
| `timeZone` | cluster TZ | e.g. `Europe/Berlin`. |
| `concurrencyPolicy` | `Forbid` | `Allow` / `Forbid` / `Replace`. |
| `suspend` | `false` | |
| `startingDeadlineSeconds` | — | |
| `successfulJobsHistoryLimit` | `3` | |
| `failedJobsHistoryLimit` | `1` | |

### Routing

**`httpRoute`** attaches to the existing platform Gateway (Gateway API):

| Key | Description |
|---|---|
| `enabled` | Renders HTTPRoute `<fullname>`. |
| `parentName` / `parentNamespace` | The platform Gateway. `parentName` is required. |
| `sectionName` | Gateway listener, default `http`. |
| `hostnames` | List of hostnames. |
| `backends` | `[{ path: /api, service: api, port: 8000, pathType: PathPrefix }]`. `service` is an **app key**, which the chart turns into `<fullname>-api`. |

**`backendTrafficPolicy`** only renders when `httpRoute.enabled`:

- `timeout`, e.g. `10s`.
- `rateLimit.type`: `Local` needs no extra infrastructure. `Global` needs the Envoy rate-limit service.
- `rateLimit.requests` and `rateLimit.unit` (`Second`/`Minute`/`Hour`/`Day`).

**`securityPolicy`** only renders when `httpRoute.enabled`. It sets CORS:

- `allowOrigins`
- `allowMethods` (default GET/POST/PUT/DELETE)
- `allowHeaders` (default Authorization/Content-Type)

**`ingress`** is the classic Ingress alternative, for clusters without Gateway API:

- `className`, `host`, `annotations`, `tls`
- `paths: [{ path, service, port, pathType }]`. `service` is an app key, as above.

### `serviceMonitor` (Prometheus Operator)

| Key | Default | Description |
|---|---|---|
| `enabled` | `false` | Selects **all** Services in the release. |
| `portName` | `http` | Scrapes only Service ports with this name. |
| `path` / `interval` | `/metrics` / `30s` | |
| `additionalLabels` | `{}` | e.g. `release: kube-prometheus-stack`, which that stack needs before it picks the ServiceMonitor up. |

---

## How it works

### One pod template

[`templates/_pod.tpl`](templates/_pod.tpl) is the only place a pod is defined. [`workloads.yaml`](templates/workloads.yaml), [`jobs.yaml`](templates/jobs.yaml) and [`cronjobs.yaml`](templates/cronjobs.yaml) only add the parts specific to their kind: replicas and PVCs, hook annotations, schedule.

- Add a new pod-level feature once in `_pod.tpl`, and apps, jobs and cron jobs all get it.
- [`_job.tpl`](templates/_job.tpl) holds the Job spec that Job and CronJob share.
- [`_names.tpl`](templates/_names.tpl) holds names, labels and metadata.

### Config changes roll pods, but only the pods that use them

A pod gets a `checksum/config` or `checksum/secret` annotation only if it reads that object, through `envFrom*` or a `*KeyRef` in `envValueFrom`. Changing a ConfigMap value restarts the pods that read it and leaves the others alone.

A Secret given with `secret.existing` isn't rendered by the chart, so it has no checksum. Restart pods yourself when it changes, or use a reloader.

### Hook Jobs and what they depend on

A `pre-install` hook runs **before** the release's normal resources are created. Without help, a migration Job using `envFromSecret` would fail on the first install because the Secret wouldn't exist yet.

When any enabled job has a `pre-*` hook, the chart therefore turns the **ConfigMap, Secret and ServiceAccount into hooks** with weight `-10`. That way they're created before the job, which runs at weight `0`. Install order for `examples/demo-values.yaml`:

```
weight -10: ServiceAccount demo, Secret demo-secret, ConfigMap demo-config
weight   0: Job demo-migrate   ← must succeed, or the install stops here
then:       Deployments, Services, plain Jobs, CronJobs, routes...
```

### Security defaults

Pods don't mount a ServiceAccount API token unless `serviceAccount.automountServiceAccountToken: true`.

There's no default security context, because many popular images (nginx, redis, mongo) start as root and would fail under `runAsNonRoot`. Set a hardened baseline in `defaults` and relax it per app where needed. `backend-values.yaml` does exactly that: the release runs as uid 1000 with all capabilities dropped, and Mongo overrides `podSecurityContext` to run as its own user, 999.

---

## Validation

[`values.schema.json`](values.schema.json) is checked by `helm install`, `upgrade`, `template` and `lint`. Unknown keys, typos, wrong types and invalid enum values fail immediately, with the exact path:

```
- at '/apps/web': additional properties 'envFromSecrt' not allowed
- at '/apps/web/replicas': got string, want integer
- at '': additional properties 'cronjob' not allowed
```

Templates also fail with clear messages when:

- `image` is missing or isn't a string
- `schedule` or `persistence.mountPath` is missing
- `secret.create` has empty `data`
- `secret.create` and `secret.existing` are both set
- `kind` or `rateLimit.type` is invalid
- `httpRoute.parentName` is missing

---

## Caveats

- **Hook resources outlive the release.** When a pre-hook job is enabled, the ConfigMap, Secret and ServiceAccount are hooks, and `helm uninstall` doesn't delete them. Remove them manually:
  ```bash
  kubectl delete cm,secret,sa -l app.kubernetes.io/instance=<release>
  ```
- **Adding a pre-hook job to an existing release.** The ConfigMap, Secret and ServiceAccount switch from regular release resources to hooks. On that upgrade Helm can delete them as "removed from the release" right after the hook recreated them. Uninstall and reinstall instead, or delete those three objects before upgrading. Fresh installs aren't affected.
- **Plain Jobs re-run on upgrade.** A Job's pod template can't be changed after creation, so plain jobs default to `ttlSecondsAfterFinished: 600`. Once a job has expired, the next `helm upgrade` recreates it, which runs it again. Make plain jobs idempotent, or make them a hook such as `post-install`.
- **`envValueFrom` uses full resource names.** For example `backend-secret`, not `secret`. These names depend on `fullnameOverride`.
- **A route's `service` isn't checked against `apps`.** A typo renders an HTTPRoute pointing to a Service that doesn't exist. Check `helm template` output.

---

## Upgrading from 0.1.x

0.2.0 changes the values format, and the schema rejects the old keys.

| 0.1.x | 0.2.0 |
|---|---|
| `job: { enabled, name: seed, image, tag, ... }` | `jobs: { seed: { enabled, image: "repo:tag", ... } }` |
| `hooks.preInstall: { enabled, image, tag, ... }` | `jobs: { migrate: { enabled, image: "repo:tag", hook: pre-install,pre-upgrade } }` |
| `cronjob: { enabled, name: cleanup, ... }` | `cronJobs: { cleanup: { enabled, schedule, image, ... } }` |
| `image: { repository, tag, pullPolicy }` | `image: "repository:tag"` + `imagePullPolicy` |
| — | `serviceAccount`, `defaults`, `secret.existing` (new) |

Rendering changes for an existing release:

- **Resource names:**
  - The hook Job is now `<fullname>-<key>` (e.g. `-migrate` instead of `-pre-install`).
  - CronJob component labels and container names are now the entry key instead of `cronjob`/`cron`.
- **Defaults:**
  - CronJob `backoffLimit` defaults to `2` instead of `1`.
  - An image without a tag no longer falls back to `appVersion`.
- **Pod spec:**
  - Pods now set `serviceAccountName` and `automountServiceAccountToken: false`.
  - Pods that don't read the ConfigMap or Secret no longer carry their checksums. This rolls them once on the first upgrade.

---

## Developing the chart

```bash
helm lint generic-chart -f examples/backend-values.yaml --set secret.data.MONGO_PASSWORD=x
helm template t generic-chart -f examples/demo-values.yaml --set secret.data.DB_PASSWORD=x
```

- **New value:** add it to `values.yaml` (commented example), to `values.schema.json` (or the schema rejects it), and to this README.
- **New pod-level field:** add it in `_pod.tpl`. If it's a plain pass-through that should support release-wide defaults, add its name to the two key lists at the top of `podTemplate` and to `defaults` in the schema.
- Keep feature logic (what a resource contains) in its own template file. Helpers are only for what several templates share.
