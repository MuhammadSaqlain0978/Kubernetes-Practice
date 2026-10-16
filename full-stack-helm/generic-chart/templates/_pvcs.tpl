{{/* persistentVolumeClaims.<key> → PVC <fullname>[-<key>], mounted with
     volumes: [{name, pvc: <key>}]. For one PVC PER POD use a StatefulSet's
     persistence instead. */}}
{{- define "generic-chart.persistentVolumeClaims" -}}
{{- range $key, $pvc := .Values.persistentVolumeClaims }}
{{- if $pvc.enabled }}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  {{- include "generic-chart.metadata" (dict "root" $ "key" $key "annotations" (ternary (dict "helm.sh/resource-policy" "keep") dict (default false $pvc.keep))) | nindent 2 }}
spec:
  accessModes:
    {{- toYaml ($pvc.accessModes | default (list "ReadWriteOnce")) | nindent 4 }}
  {{- with $pvc.storageClassName }}
  storageClassName: {{ . }}
  {{- end }}
  resources:
    requests:
      storage: {{ required (printf "persistentVolumeClaims.%s.size is required" $key) $pvc.size }}
{{- end }}
{{- end }}
{{- end }}
