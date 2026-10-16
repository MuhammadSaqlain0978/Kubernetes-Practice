{{/*
=============================================================================
generic-chart helpers — every helper function lives in this file.
Resource templates are the other _*.tpl files (one per kind); app.yaml
includes them all. Defaults are in ../values.yaml.
=============================================================================
*/}}

{{/* ----------------------------------------------------------------------
   NAMES, LABELS, METADATA
   ---------------------------------------------------------------------- */}}

{{- define "generic-chart.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Base name for every resource — set fullnameOverride to the application name */}}
{{- define "generic-chart.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name (include "generic-chart.name" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Name of a keyed resource: <fullname>-<key>, or just <fullname> for the key
"default". Used for EVERY map in values (apps, configMaps, secrets, httpRoutes...).
  dict "root" $ "key" <key>
*/}}
{{- define "generic-chart.resourceName" -}}
{{- $full := include "generic-chart.fullname" .root }}
{{- if eq (toString .key) "default" }}
{{- $full }}
{{- else }}
{{- printf "%s-%s" $full (toString .key) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{- define "generic-chart.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | quote }}
{{ include "generic-chart.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/* Selector labels — no component, so ServiceMonitor can select ALL chart services */}}
{{- define "generic-chart.selectorLabels" -}}
app.kubernetes.io/name: {{ include "generic-chart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Standard object metadata: name + labels [+ annotations].
  dict "root" $  "key" <values key, "default" = no suffix>
       "component" "<label>" (optional)  "labels" {}  "annotations" {}
*/}}
{{- define "generic-chart.metadata" -}}
name: {{ include "generic-chart.resourceName" (dict "root" .root "key" .key) }}
labels:
  {{- include "generic-chart.labels" .root | nindent 2 }}
  {{- with .component }}
  app.kubernetes.io/component: {{ . }}
  {{- end }}
  {{- with .labels }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
{{- with .annotations }}
annotations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{/* ServiceAccount every pod in the release runs as */}}
{{- define "generic-chart.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- .Values.serviceAccount.name | default (include "generic-chart.fullname" .) }}
{{- else }}
{{- .Values.serviceAccount.name | default "default" }}
{{- end }}
{{- end }}

{{/*
A pre-install job runs BEFORE normal resources exist, so when any enabled job
is a pre-* hook, the ConfigMaps, Secrets, ExternalSecrets and ServiceAccount it
may depend on become hooks too (weight -10 = created before the job at 0).
*/}}
{{- define "generic-chart.preHookAnnotations" -}}
{{- $pre := false }}
{{- range $name, $job := .Values.jobs }}
{{- if and $job.enabled (contains "pre-" ($job.hook | default "")) }}
{{- $pre = true }}
{{- end }}
{{- end }}
{{- if $pre }}
helm.sh/hook: pre-install,pre-upgrade
helm.sh/hook-weight: "-10"
helm.sh/hook-delete-policy: before-hook-creation
{{- end }}
{{- end }}

{{/* ----------------------------------------------------------------------
   REFERENCES — resolve a values key to a resource name, failing on typos
   ---------------------------------------------------------------------- */}}

{{/* Service of apps.<service>, which must be enabled with service.enabled
     dict "root" $ "service" <app key> "path" "<where, for errors>" */}}
{{- define "generic-chart.serviceRef" -}}
{{- $app := index .root.Values.apps (toString .service) }}
{{- if not (and $app $app.enabled ($app.service).enabled) }}
{{- fail (printf "%s: service %q must be an enabled apps.<key> with service.enabled: true" .path (toString .service)) }}
{{- end }}
{{- include "generic-chart.resourceName" (dict "root" .root "key" .service) }}
{{- end }}

{{/* HTTPRoute of httpRoutes.<route>, which must be enabled
     dict "root" $ "route" <key> "path" "<where>" */}}
{{- define "generic-chart.routeRef" -}}
{{- $r := index .root.Values.httpRoutes (toString .route) }}
{{- if not (and $r $r.enabled) }}
{{- fail (printf "%s: route %q must be an enabled httpRoutes.<key>" .path (toString .route)) }}
{{- end }}
{{- include "generic-chart.resourceName" (dict "root" .root "key" .route) }}
{{- end }}

{{/* ConfigMap / Secret / PVC of a values map key, which must exist and be enabled.
     Secrets may come from secrets.<key> or externalSecrets.<key>.
     dict "root" $ "kind" "configMaps"|"secrets"|"persistentVolumeClaims" "key" <key> "path" "<where>" */}}
{{- define "generic-chart.objectRef" -}}
{{- $found := false }}
{{- $maps := list .kind }}
{{- if eq .kind "secrets" }}{{ $maps = list "secrets" "externalSecrets" }}{{ end }}
{{- range $m := $maps }}
{{- $o := index (index $.root.Values $m | default dict) (toString $.key) }}
{{- if and $o $o.enabled }}{{ $found = true }}{{ end }}
{{- end }}
{{- if not $found }}
{{- fail (printf "%s: %q must be an enabled %s.<key>" .path (toString .key) (join " or " $maps)) }}
{{- end }}
{{- include "generic-chart.resourceName" (dict "root" .root "key" .key) }}
{{- end }}

{{/* ----------------------------------------------------------------------
   POD TEMPLATE — shared by apps, jobs, cronJobs and tests
     dict "root" $  "name" <key>  "spec" <values entry>  "path" "apps.<key>"
          "kind" <workload kind> (optional)  "restartPolicy" <policy> (optional)
   Scheduling/security fields come from .Values.defaults; an entry (or a
   container, for securityContext) that sets the same key replaces it.
   ---------------------------------------------------------------------- */}}

{{- define "generic-chart.podTemplate" -}}
{{- $root := .root }}
{{- $s := .spec }}
{{- $path := .path }}
{{- if not $s.containers }}
{{- fail (printf "%s.containers needs at least one container" $path) }}
{{- end }}
{{- $pick := dict }}
{{- range $k := list "podSecurityContext" "securityContext" "nodeSelector" "tolerations" "affinity" "imagePullSecrets" }}
{{- $_ := set $pick $k (hasKey $s $k | ternary (index $s $k) (index $root.Values.defaults $k)) }}
{{- end }}
{{- $ann := include "generic-chart.checksums" . | fromYaml }}
{{- $ann = mergeOverwrite $ann ($s.annotations | default dict) -}}
metadata:
  labels:
    {{- include "generic-chart.selectorLabels" $root | nindent 4 }}
    app.kubernetes.io/component: {{ .name }}
  {{- with $ann }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  serviceAccountName: {{ include "generic-chart.serviceAccountName" $root }}
  automountServiceAccountToken: {{ $root.Values.serviceAccount.automountServiceAccountToken | default false }}
  {{- with .restartPolicy }}
  restartPolicy: {{ . }}
  {{- end }}
  {{- with $pick.podSecurityContext }}
  securityContext:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- range $k := list "imagePullSecrets" "nodeSelector" "tolerations" "affinity" }}
  {{- with index $pick $k }}
  {{ $k }}:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- end }}
  {{- with $s.volumes }}
  volumes:
    {{- range $i, $v := . }}
    {{- $vpath := printf "%s.volumes[%d]" $path $i }}
    - name: {{ required (printf "%s.name is required" $vpath) $v.name }}
      {{- if $v.configMap }}
      configMap:
        name: {{ include "generic-chart.objectRef" (dict "root" $root "kind" "configMaps" "key" $v.configMap "path" $vpath) }}
        {{- with $v.items }}
        items:
          {{- toYaml . | nindent 10 }}
        {{- end }}
      {{- else if $v.secret }}
      secret:
        secretName: {{ include "generic-chart.objectRef" (dict "root" $root "kind" "secrets" "key" $v.secret "path" $vpath) }}
        {{- with $v.items }}
        items:
          {{- toYaml . | nindent 10 }}
        {{- end }}
      {{- else if $v.pvc }}
      persistentVolumeClaim:
        claimName: {{ include "generic-chart.objectRef" (dict "root" $root "kind" "persistentVolumeClaims" "key" $v.pvc "path" $vpath) }}
      {{- else if hasKey $v "emptyDir" }}
      emptyDir: {{ $v.emptyDir | default dict | toJson }}
      {{- else }}
      {{- fail (printf "%s needs one of configMap, secret, pvc or emptyDir" $vpath) }}
      {{- end }}
    {{- end }}
  {{- end }}
  containers:
    {{- range $i, $c := $s.containers }}
    {{- include "generic-chart.container" (dict "root" $root "c" $c "first" (eq $i 0) "pick" $pick "kind" $.kind "spec" $s "path" (printf "%s.containers[%d]" $path $i)) | nindent 4 }}
    {{- end }}
{{- end }}

{{/* One container. dict "root" "c" "first" "pick" "kind" "spec" "path" */}}
{{- define "generic-chart.container" -}}
{{- $root := .root }}
{{- $c := .c }}
{{- $image := $c.image | default $root.Values.image }}
{{- if not (and (kindIs "string" $image) $image) }}
{{- fail (printf "%s.image is required (or set the release-wide image), e.g. \"busybox:1.36\"" .path) }}
{{- end -}}
- name: {{ required (printf "%s.name is required" .path) $c.name }}
  image: {{ $image | quote }}
  imagePullPolicy: {{ $c.imagePullPolicy | default $root.Values.imagePullPolicy | default "IfNotPresent" }}
  {{- with $c.command }}
  command:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $c.args }}
  args:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $c.ports }}
  ports:
    {{- range . }}
    - name: {{ .name }}
      containerPort: {{ .containerPort }}
      protocol: {{ .protocol | default "TCP" }}
    {{- end }}
  {{- end }}
  {{- with $c.probes }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
  {{- with $c.lifecycle }}
  lifecycle:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $c.resources }}
  resources:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with (hasKey $c "securityContext" | ternary $c.securityContext .pick.securityContext) }}
  securityContext:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- if or $c.env $c.envValueFrom }}
  env:
    {{- range $key, $value := $c.env }}
    - name: {{ $key }}
      value: {{ $value | quote }}
    {{- end }}
    {{- range $key, $ref := $c.envValueFrom }}
    - name: {{ $key }}
      valueFrom:
        {{- toYaml $ref | nindent 8 }}
    {{- end }}
  {{- end }}
  {{- if or $c.envFromConfigMaps $c.envFromSecrets }}
  envFrom:
    {{- range $c.envFromConfigMaps }}
    - configMapRef:
        name: {{ include "generic-chart.objectRef" (dict "root" $root "kind" "configMaps" "key" . "path" (printf "%s.envFromConfigMaps" $.path)) }}
    {{- end }}
    {{- range $c.envFromSecrets }}
    - secretRef:
        name: {{ include "generic-chart.objectRef" (dict "root" $root "kind" "secrets" "key" . "path" (printf "%s.envFromSecrets" $.path)) }}
    {{- end }}
  {{- end }}
  {{- $persist := and .first (eq (.kind | default "") "StatefulSet") .spec.persistence }}
  {{- if or $c.volumeMounts $persist }}
  volumeMounts:
    {{- with $c.volumeMounts }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
    {{- if $persist }}
    - name: data
      mountPath: {{ required (printf "%s.persistence.mountPath is required" (trimSuffix ".containers[0]" .path)) .spec.persistence.mountPath }}
    {{- end }}
  {{- end }}
{{- end }}

{{/*
Pod annotations that roll pods when config they consume changes — one per
chart-managed ConfigMap/Secret the pod references (envFrom*, volumes, or a
*KeyRef in envValueFrom). ExternalSecrets have no data here, so no checksum.
  same dict as podTemplate
*/}}
{{- define "generic-chart.checksums" -}}
{{- $root := .root }}
{{- $s := .spec }}
{{- $keyRefs := list }}
{{- range $s.containers }}{{ $keyRefs = append $keyRefs (toYaml .envValueFrom) }}{{ end }}
{{- $keyRefs = join "\n" $keyRefs }}
{{- range $kind := list "configMaps" "secrets" }}
{{- $field := ternary "configMap" "secret" (eq $kind "configMaps") }}
{{- $envList := ternary "envFromConfigMaps" "envFromSecrets" (eq $kind "configMaps") }}
{{- range $key, $obj := index $root.Values $kind }}
{{- if $obj.enabled }}
{{- $name := include "generic-chart.resourceName" (dict "root" $root "key" $key) }}
{{- $used := contains (printf "name: %s\n" $name) $keyRefs }}
{{- range $s.volumes }}{{ if eq (toString (index . $field | default "")) $key }}{{ $used = true }}{{ end }}{{ end }}
{{- range $s.containers }}{{ if has $key (index . $envList | default list) }}{{ $used = true }}{{ end }}{{ end }}
{{- if $used }}
checksum/{{ $field | lower }}-{{ $key }}: {{ toYaml $obj.data | sha256sum }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/* ----------------------------------------------------------------------
   JOB SPEC — shared by Job and CronJob.jobTemplate
     dict "root" $  "name" <key>  "spec" <values entry>  "path" "jobs.<key>"
   ---------------------------------------------------------------------- */}}

{{- define "generic-chart.jobSpec" -}}
{{- $s := .spec -}}
backoffLimit: {{ hasKey $s "backoffLimit" | ternary $s.backoffLimit 2 }}
{{- with $s.activeDeadlineSeconds }}
activeDeadlineSeconds: {{ . }}
{{- end }}
{{- if hasKey $s "ttlSecondsAfterFinished" }}
ttlSecondsAfterFinished: {{ $s.ttlSecondsAfterFinished }}
{{- end }}
template:
  {{- include "generic-chart.podTemplate" (merge (dict "restartPolicy" ($s.restartPolicy | default "Never")) .) | nindent 2 }}
{{- end }}

{{/* ----------------------------------------------------------------------
   ENVOY GATEWAY POLICY — shared by BackendTrafficPolicy and SecurityPolicy.
   Everything except enabled/targetHttpRoutes is passed into spec as-is.
     dict "root" $ "key" <key> "policy" <values entry> "path" "<values path>"
   ---------------------------------------------------------------------- */}}

{{- define "generic-chart.policySpec" -}}
targetRefs:
  {{- range (.policy.targetHttpRoutes | default (list "default")) }}
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: {{ include "generic-chart.routeRef" (dict "root" $.root "route" . "path" (printf "%s.targetHttpRoutes" $.path)) }}
  {{- end }}
{{- with omit .policy "enabled" "targetHttpRoutes" }}
{{ toYaml . }}
{{- end }}
{{- end }}
