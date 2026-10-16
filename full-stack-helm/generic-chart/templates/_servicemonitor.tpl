{{/* serviceMonitor → ServiceMonitor <fullname>, scraping every Service in the
     release that has a port named serviceMonitor.portName */}}
{{- define "generic-chart.serviceMonitor" -}}
{{- if .Values.serviceMonitor.enabled }}
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  {{- include "generic-chart.metadata" (dict "root" . "key" "default" "labels" .Values.serviceMonitor.additionalLabels) | nindent 2 }}
spec:
  selector:
    matchLabels:
      {{- include "generic-chart.selectorLabels" . | nindent 6 }}
  endpoints:
    - port: {{ .Values.serviceMonitor.portName | default "http" }}
      path: {{ .Values.serviceMonitor.path | default "/metrics" }}
      interval: {{ .Values.serviceMonitor.interval | default "30s" }}
      {{- with .Values.serviceMonitor.scrapeTimeout }}
      scrapeTimeout: {{ . }}
      {{- end }}
{{- end }}
{{- end }}
