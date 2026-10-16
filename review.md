# PR review: full-stack-helm

## Summary comment (post on the PR)

Nice work on this — getting a frontend, backend, MongoDB, Gateway API and a full observability stack running together in one chart is a lot of moving parts, and the overall structure makes sense. A few things I especially liked:

- Choosing Gateway API / Envoy Gateway over ingress-nginx (good call, ingress-nginx is being retired)
- The HPA `behavior` tuning to avoid flapping
- Using `volumeClaimTemplates` on the MongoDB StatefulSet
- Multi-stage build for the frontend image

The main theme of the feedback: **right now the chart only works on your dev cluster, in the `dev` namespace, with your local images.** The goal of a Helm chart is that someone else can `helm install` it anywhere and toggle features from `values.yaml`. Most comments below are about getting there.

Labels I'm using:
- **[must fix]** — blocks merge
- **[should fix]** — please address in this PR if you can, or open a follow-up
- **[nit]** — small cleanup, your call

Please run `helm template . | less` after your changes and read the rendered output — it's the fastest way to catch most of these yourself. Happy to pair on any of it!

---

## `templates/secret.yaml`

**[must fix]** Real credentials (`admin` / `password123`) are committed to git. Even for a practice project, it's worth building the habit: anything in git history should be treated as public, and deleting the file later doesn't remove it from history.

Options, from simplest to most production-like:
1. Pass them at install time: `helm install ... --set mongodb.auth.password=...` and use `{{ required "mongodb.auth.password is required" .Values.mongodb.auth.password }}` in the template.
2. Sealed Secrets (encrypted secret that's safe to commit).
3. External Secrets Operator pulling from AWS Secrets Manager (what we'd do on EKS).

If this password was used anywhere real, please rotate it.

---

## `values.yaml` + `templates/ingress.yaml` (and other optional resources)

**[must fix]** Several flags in `values.yaml` aren't read by any template, so changing them does nothing:
`ingress.enabled`, `ingress.tls.enabled`, `gateway.enabled`, `gateway.tls.*`, `backend.hpa.enabled`, `certManager.enabled`, `envoyProxy.service.type`.

For example, `ingress.enabled: false` but `helm template` still renders the Ingress — with an empty cert-manager annotation and an empty TLS `secretName`, so it would be created broken.

Wrap each optional resource like this:

```yaml
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
...
{{- end }}
```

---

## `templates/gateway.yaml`, `httproute.yaml`, `*-policy.yaml`, `instrumentation.yaml`

**[must fix]** These hardcode `namespace: dev`, while the Deployments/Services/Secret use the release namespace. If someone runs `helm install -n staging`, the HTTPRoute in `dev` will point at Services that don't exist there, and auto-instrumentation won't inject into the pods.

Use `namespace: {{ .Release.Namespace }}` (or just leave `namespace` out — Helm applies the release namespace by default).

Related: `envoy-proxy.yaml` deploys into `envoy-gateway-system` and `otel-servicemonitor.yaml` into `observability`. An app chart shouldn't create things in namespaces it doesn't own — these belong in a separate "platform" chart or in the values for those tools.

---

## `templates/envoy-proxy.yaml`

**[must fix]** This `EnvoyProxy` resource isn't referenced by anything, so the `NodePort` setting is never applied. An EnvoyProxy only takes effect when a GatewayClass (`spec.parametersRef`) or a Gateway (`spec.infrastructure.parametersRef`) points to it — and the GatewayClass is commented out.

Either un-comment the GatewayClass and add `parametersRef` pointing to `internet-facing-proxy`, or move the EnvoyProxy into the same namespace as the Gateway and reference it from the Gateway. Verify with `kubectl get svc -n envoy-gateway-system` that the type actually changed.

---

## `templates/Backend-traffic-policy.yaml`

**[must fix]** Two problems with the rate limit:

1. It's keyed on the `X-Forwarded-For` header, which the client controls. Combined with `numTrustedHops: 1` and no load balancer in front (NodePort), a client can send a different fake XFF on every request and never get limited. Try it: `curl -H "X-Forwarded-For: 1.2.3.$RANDOM" ...`
2. `type: Global` requires Redis to be configured in Envoy Gateway. Without it, the policy isn't enforced — check `kubectl describe backendtrafficpolicy api-rate-limit` for the status.

Suggested:

```yaml
rateLimit:
  type: Local
  local:
    rules:
      - clientSelectors:
          - sourceCIDR:
              type: Distinct
              value: 0.0.0.0/0
        limit:
          requests: 100
          unit: Minute
```

Also **[nit]**: rename the file to lowercase (`backend-traffic-policy.yaml`) to match the others.

---

## `templates/backend-deployment.yaml`

**[should fix]** No readiness/liveness probes. Kubernetes will send traffic to the pod as soon as the container starts, even if it can't reach MongoDB. You already have `/api/health` — let's use it:

```yaml
readinessProbe:
  httpGet:
    path: /api/health
    port: 8000
  periodSeconds: 10
livenessProbe:
  httpGet:
    path: /api/health
    port: 8000
  initialDelaySeconds: 15
  periodSeconds: 20
```

For readiness to mean anything, `/api/health` should return 503 when `mongoose.connection.readyState !== 1` (see the `server.js` comment).

**[should fix]** `replicas: {{ .Values.backend.replicas }}` conflicts with the HPA — every `helm upgrade` resets the count back to 2, undoing the autoscaling. Only set replicas when the HPA is off:

```yaml
{{- if not .Values.backend.hpa.enabled }}
replicas: {{ .Values.backend.replicas }}
{{- end }}
```

**[should fix]** Pods won't restart when the ConfigMap or Secret changes. Add checksum annotations to the pod template so Helm rolls them automatically:

```yaml
annotations:
  checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
  checksum/secret: {{ include (print $.Template.BasePath "/secret.yaml") . | sha256sum }}
```

**[nit]** `containerPort` uses `.Values.backend.service.port` — it should be `targetPort` (the container's port, not the Service's). They happen to be equal today.

---

## `templates/frontend-deployment.yaml` / `mongodb-statefulset.yaml`

**[should fix]** No `resources.requests/limits`. Without requests, these pods get "BestEffort" QoS and are the first to be evicted when a node runs low on memory — losing MongoDB that way is painful. Also add probes (nginx: `httpGet /`; Mongo: `exec` with `mongosh --eval "db.adminCommand('ping')"`).

**[should fix]** Add a basic `securityContext` to all containers:

```yaml
securityContext:
  runAsNonRoot: true
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true   # nginx needs an emptyDir for /var/cache/nginx and /tmp
  capabilities:
    drop: ["ALL"]
```

For the frontend that means switching to `nginxinc/nginx-unprivileged` and listening on 8080.

---

## `templates/mongodb-service.yaml`

**[should fix]** A StatefulSet's `serviceName` should point to a **headless** Service (`clusterIP: None`) so each pod gets a stable DNS name (`mongodb-0.mongodb`). Keep the current one for clients if you like, but add a headless one for the StatefulSet.

Also in `values.yaml`: `storageClass: standard` exists on kind/minikube, but not on EKS (`gp2`/`gp3`). Good candidate for a per-environment values file (`values-eks.yaml`).

---

## `templates/configmap.yaml` / `httproute.yaml`

**[should fix]** Port `8000` is hardcoded in four places (ConfigMap, values, HTTPRoute, Deployment), and the backend Dockerfile says `EXPOSE 5000`. Change one and something silently breaks. Reference `.Values.backend.service.port` everywhere. Same for `APP_ENV: "dev"` — make it a value.

---

## `values.yaml` (images)

**[should fix]** `repository: full-stack-backend` / `tag: "1.0"` don't match what `commands.txt` pushes (`<account>.dkr.ecr.us-west-1.amazonaws.com/eks_repo:backend-1.0`), so on EKS this would be `ImagePullBackOff`.

Also, reusing a tag like `1.0` with `pullPolicy: IfNotPresent` means nodes keep running the old image after you push a new one. Prefer a unique tag per build (e.g. the git SHA).

**[nit]** `instrumentation.yaml` uses `:latest` for the auto-instrumentation images — pin a version so behavior doesn't change underneath you.

---

## `otel-collector-values.yaml`

**[should fix]** The Instrumentation sends **traces** to the collector, but the collector only has `metrics` and `logs` pipelines, so traces are dropped. Add a `traces` pipeline with an exporter (Tempo/Jaeger), or turn trace export off if you don't need it yet.

**[nit]** The `loki` exporter is deprecated and removed in newer collector versions. Loki 3 accepts OTLP directly — use the `otlphttp` exporter with `endpoint: http://loki.monitoring.svc.cluster.local:3100/otlp`.

---

## `app/backend/server.js`

**[should fix]** The Mongo username/password are put into the URI without encoding, so a password with `@`, `:` or `/` breaks the connection string. Wrap them in `encodeURIComponent(...)`.

**[should fix]** If the Mongo connection fails, the error is logged but the app keeps serving and `/api/health` still says "healthy". Make health reflect the DB state:

```js
app.get("/api/health", (req, res) => {
  const ok = mongoose.connection.readyState === 1;
  res.status(ok ? 200 : 503).json({ status: ok ? "healthy" : "unhealthy" });
});
```

---

## `app/*/Dockerfile`

**[should fix]**
- There's no `package-lock.json` committed, so every build can pull different dependency versions. Commit the lockfiles and use `npm ci` (backend: `npm ci --omit=dev`).
- Add a `.dockerignore` with `node_modules` so local modules don't get copied into the image.
- Backend: add `USER node` and use `CMD ["node", "server.js"]` so the process receives SIGTERM directly and shuts down cleanly.
- Backend `EXPOSE 5000` should be `8000`.

---

## Cleanup **[nit]**

- Delete the fully commented-out templates (`certificate.yaml`, `clusterissuer.yaml`, `gatewayclass.yaml`, `storageclass.yaml`, `otel-podmonitor.yaml`) or turn them into flag-gated templates. Git keeps the history.
- `templates/loki-values.yaml` is empty and isn't a template — remove it.
- `Chart.yaml`: replace the boilerplate `appVersion: "1.16.0"` and example icon.
- Add `commands.txt`, `app/`, `*-values.yaml` to `.helmignore` so they aren't packaged into the chart.
- `commands.txt`: the ECR login is duplicated, and `REPO_URI = ...` isn't valid shell (no spaces around `=`). Consider turning this into a `Makefile` — and avoid committing the AWS account ID / personal email (ClusterIssuer).
- Longer term: add a `_helpers.tpl` with standard `app.kubernetes.io/*` labels and name helpers so two releases don't collide on hardcoded names like `backend`.

---

### Suggested order
1. Secret out of git
2. `enabled` flags
3. `.Release.Namespace`
4. EnvoyProxy wiring + rate limit
5. Probes / resources / HPA replicas
6. Everything else (fine as follow-up PRs)
