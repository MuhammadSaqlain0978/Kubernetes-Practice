{{/* httpRoutes.<key> → HTTPRoute <fullname>[-<key>] on the platform Gateway.
     matches/filters are raw Gateway API; backendRefs name apps by key. */}}
{{- define "generic-chart.httpRoutes" -}}
{{- range $key, $r := .Values.httpRoutes }}
{{- if $r.enabled }}
{{- $path := printf "httpRoutes.%s" $key }}
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  {{- include "generic-chart.metadata" (dict "root" $ "key" $key) | nindent 2 }}
spec:
  parentRefs:
    {{- toYaml (required (printf "%s.parentRefs is required (the platform Gateway)" $path) $r.parentRefs) | nindent 4 }}
  {{- with $r.hostnames }}
  hostnames:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  rules:
    {{- range $i, $rule := (required (printf "%s.rules is required" $path) $r.rules) }}
    - backendRefs:
        {{- range $j, $b := (required (printf "%s.rules[%d].backendRefs is required" $path $i) $rule.backendRefs) }}
        - name: {{ include "generic-chart.serviceRef" (dict "root" $ "service" $b.service "path" (printf "%s.rules[%d].backendRefs[%d]" $path $i $j)) }}
          port: {{ required (printf "%s.rules[%d].backendRefs[%d].port is required" $path $i $j) $b.port }}
          {{- with $b.weight }}
          weight: {{ . }}
          {{- end }}
        {{- end }}
      {{- with $rule.matches }}
      matches:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $rule.filters }}
      filters:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $rule.timeouts }}
      timeouts:
        {{- toYaml . | nindent 8 }}
      {{- end }}
    {{- end }}
{{- end }}
{{- end }}
{{- end }}
