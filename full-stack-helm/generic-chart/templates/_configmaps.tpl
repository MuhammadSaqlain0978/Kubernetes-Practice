{{/* configMaps.<key> → ConfigMap <fullname>[-<key>]. Use as env (envFromConfigMaps)
     or as files (volumes: [{name, configMap: <key>}]). */}}
{{- define "generic-chart.configMaps" -}}
{{- range $key, $cm := .Values.configMaps }}
{{- if $cm.enabled }}
---
apiVersion: v1
kind: ConfigMap
metadata:
  {{- include "generic-chart.metadata" (dict "root" $ "key" $key "annotations" (include "generic-chart.preHookAnnotations" $ | fromYaml)) | nindent 2 }}
data:
  {{- range $k, $v := $cm.data }}
  {{ $k }}: {{ $v | toString | quote }}
  {{- end }}
{{- end }}
{{- end }}
{{- end }}
