{{/* backendTrafficPolicies.<key> → BackendTrafficPolicy <fullname>[-<key>]:
     timeout, rateLimit, circuitBreaker, retry... (Envoy Gateway spec, as-is) */}}
{{- define "generic-chart.backendTrafficPolicies" -}}
{{- range $key, $p := .Values.backendTrafficPolicies }}
{{- if $p.enabled }}
---
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: BackendTrafficPolicy
metadata:
  {{- include "generic-chart.metadata" (dict "root" $ "key" $key) | nindent 2 }}
spec:
  {{- include "generic-chart.policySpec" (dict "root" $ "key" $key "policy" $p "path" (printf "backendTrafficPolicies.%s" $key)) | nindent 2 }}
{{- end }}
{{- end }}
{{- end }}
