{{/* apps.<key>.hpa → HorizontalPodAutoscaler <fullname>[-<key>] */}}
{{- define "generic-chart.hpas" -}}
{{- range $name, $app := .Values.apps }}
{{- if and $app.enabled ($app.hpa).enabled }}
{{- $kind := $app.kind | default "Deployment" }}
{{- $hpa := $app.hpa }}
{{- $path := printf "apps.%s.hpa" $name }}
{{- if eq $kind "DaemonSet" }}
{{- fail (printf "%s: a DaemonSet can't be autoscaled (one pod per node)" $path) }}
{{- end }}
{{- if not (or $hpa.targetCPUUtilizationPercentage $hpa.targetMemoryUtilizationPercentage) }}
{{- fail (printf "%s needs targetCPUUtilizationPercentage and/or targetMemoryUtilizationPercentage" $path) }}
{{- end }}
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  {{- include "generic-chart.metadata" (dict "root" $ "key" $name "component" $name) | nindent 2 }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: {{ $kind }}
    name: {{ include "generic-chart.resourceName" (dict "root" $ "key" $name) }}
  minReplicas: {{ $hpa.minReplicas | default 1 }}
  maxReplicas: {{ required (printf "%s.maxReplicas is required" $path) $hpa.maxReplicas }}
  metrics:
    {{- range $resource, $target := dict "cpu" $hpa.targetCPUUtilizationPercentage "memory" $hpa.targetMemoryUtilizationPercentage }}
    {{- if $target }}
    - type: Resource
      resource:
        name: {{ $resource }}
        target:
          type: Utilization
          averageUtilization: {{ $target }}
    {{- end }}
    {{- end }}
  {{- with $hpa.behavior }}
  behavior:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
{{- end }}
{{- end }}
