{{/* tests.<key> → Pod <fullname>-test-<key>, run by `helm test <release>` */}}
{{- define "generic-chart.tests" -}}
{{- range $name, $t := .Values.tests }}
{{- if $t.enabled }}
{{- $pod := include "generic-chart.podTemplate" (dict "root" $ "name" (printf "test-%s" $name) "spec" $t "path" (printf "tests.%s" $name) "restartPolicy" "Never") | fromYaml }}
---
apiVersion: v1
kind: Pod
metadata:
  {{- include "generic-chart.metadata" (dict "root" $ "key" (printf "test-%s" $name) "component" (printf "test-%s" $name) "annotations" (dict "helm.sh/hook" "test" "helm.sh/hook-delete-policy" "before-hook-creation,hook-succeeded")) | nindent 2 }}
spec:
  {{- toYaml $pod.spec | nindent 2 }}
{{- end }}
{{- end }}
{{- end }}
