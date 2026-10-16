{{/*
Job spec shared by Job and CronJob.jobTemplate.
  dict "root" $  "name" <key>  "spec" <values entry>  "path" "jobs.<key>"
*/}}
{{- define "generic-chart.jobSpec" -}}
{{- $s := .spec -}}
backoffLimit: {{ hasKey $s "backoffLimit" | ternary $s.backoffLimit 2 }}
{{- with $s.activeDeadlineSeconds }}
activeDeadlineSeconds: {{ . }}
{{- end }}
{{- if hasKey $s "ttlSecondsAfterFinished" }}
ttlSecondsAfterFinished: {{ $s.ttlSecondsAfterFinished }}
{{- end }}
template:
  {{- include "generic-chart.podTemplate" (merge (dict "restartPolicy" ($s.restartPolicy | default "Never")) .) | nindent 2 }}
{{- end }}
