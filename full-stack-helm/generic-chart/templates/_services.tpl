{{/* apps.<key>.service → Service <fullname>[-<key>]. Ports default to every
     named container port of the app; service.ports overrides them. */}}
{{- define "generic-chart.services" -}}
{{- range $name, $app := .Values.apps }}
{{- if and $app.enabled ($app.service).enabled }}
{{- $ports := list }}
{{- if $app.service.ports }}
{{- $ports = $app.service.ports }}
{{- else }}
{{- range $app.containers }}
{{- range .ports }}
{{- $ports = append $ports (dict "name" .name "port" .containerPort "targetPort" .name "protocol" (.protocol | default "TCP")) }}
{{- end }}
{{- end }}
{{- end }}
{{- if not $ports }}
{{- fail (printf "apps.%s.service is enabled but no container has ports (or set service.ports)" $name) }}
{{- end }}
---
apiVersion: v1
kind: Service
metadata:
  {{- include "generic-chart.metadata" (dict "root" $ "key" $name "component" $name "annotations" $app.service.annotations) | nindent 2 }}
spec:
  type: {{ $app.service.type | default "ClusterIP" }}
  selector:
    {{- include "generic-chart.selectorLabels" $ | nindent 4 }}
    app.kubernetes.io/component: {{ $name }}
  ports:
    {{- range $ports }}
    - name: {{ .name }}
      port: {{ .port }}
      targetPort: {{ .targetPort | default .port }}
      protocol: {{ .protocol | default "TCP" }}
    {{- end }}
{{- end }}
{{- end }}
{{- end }}
