{{/* Names, labels and object metadata — used by every template */}}

{{- define "generic-chart.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "generic-chart.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name (include "generic-chart.name" .) | trunc 63 | trimSuffix "-" }}
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
Standard object metadata (name + labels [+ annotations]).
  dict "root" $  "name" "<suffix>" (optional, fullname alone when empty)
       "component" "<label>" (optional)  "labels" {}  "annotations" {}
*/}}
{{- define "generic-chart.metadata" -}}
name: {{ include "generic-chart.fullname" .root }}{{ with .name }}-{{ . }}{{ end }}
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

{{/* Secret the pods read: the chart-created one, or secret.existing */}}
{{- define "generic-chart.secretName" -}}
{{- .Values.secret.existing | default (printf "%s-secret" (include "generic-chart.fullname" .)) }}
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
is a pre-* hook, the ConfigMap, Secret and ServiceAccount it depends on become
hooks too (weight -10 = created before the job at weight 0).
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
