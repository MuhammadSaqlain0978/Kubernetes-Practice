{{/* securityPolicies.<key> → SecurityPolicy <fullname>[-<key>]:
     cors, jwt, basicAuth... (Envoy Gateway spec, as-is) */}}
{{- define "generic-chart.securityPolicies" -}}
{{- range $key, $p := .Values.securityPolicies }}
{{- if $p.enabled }}
---
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  {{- include "generic-chart.metadata" (dict "root" $ "key" $key) | nindent 2 }}
spec:
  {{- include "generic-chart.policySpec" (dict "root" $ "key" $key "policy" $p "path" (printf "securityPolicies.%s" $key)) | nindent 2 }}
{{- end }}
{{- end }}
{{- end }}
