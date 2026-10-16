{{/* externalSecrets.<key> → ExternalSecret that syncs Secret <fullname>[-<key>]
     from a SecretStore (AWS Secrets Manager, Vault...). Needs External Secrets
     Operator in the cluster. Pods use it exactly like secrets.<key>. */}}
{{- define "generic-chart.externalSecrets" -}}
{{- range $key, $es := .Values.externalSecrets }}
{{- if $es.enabled }}
{{- $path := printf "externalSecrets.%s" $key }}
{{- if not (or $es.data $es.dataFrom) }}
{{- fail (printf "%s needs data or dataFrom" $path) }}
{{- end }}
---
apiVersion: {{ $es.apiVersion | default "external-secrets.io/v1" }}
kind: ExternalSecret
metadata:
  {{- include "generic-chart.metadata" (dict "root" $ "key" $key "annotations" (include "generic-chart.preHookAnnotations" $ | fromYaml)) | nindent 2 }}
spec:
  refreshInterval: {{ $es.refreshInterval | default "1h" }}
  secretStoreRef:
    name: {{ required (printf "%s.secretStoreRef.name is required" $path) ($es.secretStoreRef).name }}
    kind: {{ ($es.secretStoreRef).kind | default "ClusterSecretStore" }}
  target:
    name: {{ include "generic-chart.resourceName" (dict "root" $ "key" $key) }}
    creationPolicy: Owner
  {{- with $es.data }}
  data:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $es.dataFrom }}
  dataFrom:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
{{- end }}
{{- end }}
