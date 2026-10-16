{{- define "generic-chart.serviceAccount" -}}
{{- if .Values.serviceAccount.create }}
{{- $annotations := mergeOverwrite (include "generic-chart.preHookAnnotations" . | fromYaml) (.Values.serviceAccount.annotations | default dict) }}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "generic-chart.serviceAccountName" . }}
  labels:
    {{- include "generic-chart.labels" . | nindent 4 }}
  {{- with $annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
automountServiceAccountToken: {{ .Values.serviceAccount.automountServiceAccountToken | default false }}
{{- end }}
{{- end }}
