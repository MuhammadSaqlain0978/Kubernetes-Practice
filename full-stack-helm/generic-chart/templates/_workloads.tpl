{{/* apps.<key> → Deployment | StatefulSet | DaemonSet <fullname>[-<key>] */}}
{{- define "generic-chart.workloads" -}}
{{- range $name, $app := .Values.apps }}
{{- if $app.enabled }}
{{- $kind := $app.kind | default "Deployment" }}
{{- if not (has $kind (list "Deployment" "StatefulSet" "DaemonSet")) }}
{{- fail (printf "apps.%s.kind must be Deployment, StatefulSet or DaemonSet (got %q)" $name $kind) }}
{{- end }}
---
apiVersion: apps/v1
kind: {{ $kind }}
metadata:
  {{- include "generic-chart.metadata" (dict "root" $ "key" $name "component" $name) | nindent 2 }}
spec:
  {{- /* DaemonSets have no replicas; with an HPA, the HPA owns the count */}}
  {{- if and (ne $kind "DaemonSet") (not ($app.hpa).enabled) (hasKey $app "replicas") }}
  replicas: {{ $app.replicas }}
  {{- end }}
  {{- with $app.revisionHistoryLimit }}
  revisionHistoryLimit: {{ . }}
  {{- end }}
  {{- with $app.strategy }}
  {{ eq $kind "Deployment" | ternary "strategy" "updateStrategy" }}:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- if eq $kind "StatefulSet" }}
  # Governing Service — the one _services.tpl creates for this app
  serviceName: {{ include "generic-chart.resourceName" (dict "root" $ "key" $name) }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "generic-chart.selectorLabels" $ | nindent 6 }}
      app.kubernetes.io/component: {{ $name }}
  template:
    {{- include "generic-chart.podTemplate" (dict "root" $ "name" $name "spec" $app "path" (printf "apps.%s" $name) "kind" $kind) | nindent 4 }}
  {{- /* Each StatefulSet pod gets its own PVC (data-<name>-0, -1, ...) that survives restarts */}}
  {{- if and (eq $kind "StatefulSet") $app.persistence }}
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes:
          - {{ $app.persistence.accessMode | default "ReadWriteOnce" }}
        {{- with $app.persistence.storageClass }}
        storageClassName: {{ . }}
        {{- end }}
        resources:
          requests:
            storage: {{ $app.persistence.size | default "1Gi" }}
  {{- end }}
{{- end }}
{{- end }}
{{- end }}
