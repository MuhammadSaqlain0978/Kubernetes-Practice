{{/* ingresses.<key> → Ingress <fullname>[-<key>] (classic alternative to httpRoutes) */}}
{{- define "generic-chart.ingresses" -}}
{{- range $key, $ing := .Values.ingresses }}
{{- if $ing.enabled }}
{{- $path := printf "ingresses.%s" $key }}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  {{- include "generic-chart.metadata" (dict "root" $ "key" $key "annotations" $ing.annotations) | nindent 2 }}
spec:
  ingressClassName: {{ $ing.className | default "nginx" }}
  {{- with $ing.tls }}
  tls:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  rules:
    {{- range $i, $rule := (required (printf "%s.rules is required" $path) $ing.rules) }}
    - host: {{ $rule.host | quote }}
      http:
        paths:
          {{- range $j, $p := $rule.paths }}
          - path: {{ $p.path | default "/" }}
            pathType: {{ $p.pathType | default "Prefix" }}
            backend:
              service:
                name: {{ include "generic-chart.serviceRef" (dict "root" $ "service" $p.service "path" (printf "%s.rules[%d].paths[%d]" $path $i $j)) }}
                port:
                  number: {{ required (printf "%s.rules[%d].paths[%d].port is required" $path $i $j) $p.port }}
          {{- end }}
    {{- end }}
{{- end }}
{{- end }}
{{- end }}
