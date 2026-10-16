{{/* secrets.<key> → Secret <fullname>[-<key>] from data. Real values only via
     --set secrets.<key>.data.KEY=... — or use externalSecrets.<key> instead. */}}
{{- define "generic-chart.secrets" -}}
{{- range $key, $sec := .Values.secrets }}
{{- if $sec.enabled }}
{{- if (index $.Values.externalSecrets $key | default dict).enabled }}
{{- fail (printf "secrets.%s and externalSecrets.%s would both create Secret %s — enable only one" $key $key (include "generic-chart.resourceName" (dict "root" $ "key" $key))) }}
{{- end }}
{{- if not $sec.data }}
{{- fail (printf "secrets.%s is enabled but data is empty — pass values with --set secrets.%s.data.KEY=... (never commit real values)" $key $key) }}
{{- end }}
---
apiVersion: v1
kind: Secret
metadata:
  {{- include "generic-chart.metadata" (dict "root" $ "key" $key "annotations" (include "generic-chart.preHookAnnotations" $ | fromYaml)) | nindent 2 }}
type: {{ $sec.type | default "Opaque" }}
stringData:
  {{- range $k, $v := $sec.data }}
  {{ $k }}: {{ $v | toString | quote }}
  {{- end }}
{{- end }}
{{- end }}
{{- end }}
