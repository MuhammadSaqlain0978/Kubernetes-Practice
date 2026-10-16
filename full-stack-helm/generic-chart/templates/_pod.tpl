{{/*
Pod template shared by apps, jobs and cronJobs — ONE place for the pod spec.
  dict "root" $  "name" <key>  "spec" <values entry>  "path" "apps.<key>" (for errors)
       "kind" <workload kind> (optional)  "restartPolicy" <policy> (optional)
Scheduling/security fields come from .Values.defaults; an entry that sets the
same key replaces the default (no deep merge).
*/}}
{{- define "generic-chart.podTemplate" -}}
{{- $root := .root }}
{{- $s := .spec }}
{{- if not (and (kindIs "string" $s.image) $s.image) }}
{{- fail (printf "%s.image is required as one string, e.g. \"busybox:1.36\"" .path) }}
{{- end }}
{{- /* entry value if set, else the release-wide default */}}
{{- $pick := dict }}
{{- range $k := list "podSecurityContext" "securityContext" "nodeSelector" "tolerations" "affinity" "imagePullSecrets" }}
{{- $_ := set $pick $k (hasKey $s $k | ternary (index $s $k) (index ($root.Values.defaults | default dict) $k)) }}
{{- end }}
{{- /* Roll pods only when config they actually consume changes */}}
{{- $ann := dict }}
{{- if and $root.Values.configMap.enabled (or $s.envFromConfigMap (contains "configMapKeyRef" (toYaml $s.envValueFrom))) }}
{{- $_ := set $ann "checksum/config" (include (print $root.Template.BasePath "/configmap.yaml") $root | sha256sum) }}
{{- end }}
{{- if and $root.Values.secret.create (or $s.envFromSecret (contains "secretKeyRef" (toYaml $s.envValueFrom))) }}
{{- $_ := set $ann "checksum/secret" (include (print $root.Template.BasePath "/secret.yaml") $root | sha256sum) }}
{{- end }}
{{- $ann = mergeOverwrite $ann ($s.annotations | default dict) -}}
metadata:
  labels:
    {{- include "generic-chart.selectorLabels" $root | nindent 4 }}
    app.kubernetes.io/component: {{ .name }}
  {{- with $ann }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  serviceAccountName: {{ include "generic-chart.serviceAccountName" $root }}
  automountServiceAccountToken: {{ $root.Values.serviceAccount.automountServiceAccountToken | default false }}
  {{- with .restartPolicy }}
  restartPolicy: {{ . }}
  {{- end }}
  {{- with $pick.podSecurityContext }}
  securityContext:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- range $k := list "imagePullSecrets" "nodeSelector" "tolerations" "affinity" }}
  {{- with index $pick $k }}
  {{ $k }}:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- end }}
  containers:
    - name: {{ .name }}
      image: {{ $s.image | quote }}
      imagePullPolicy: {{ $s.imagePullPolicy | default "IfNotPresent" }}
      {{- with $s.command }}
      command:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $s.args }}
      args:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $s.port }}
      ports:
        - containerPort: {{ . }}
      {{- end }}
      {{- with $s.probes }}
      {{- toYaml . | nindent 6 }}
      {{- end }}
      {{- with $s.resources }}
      resources:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $pick.securityContext }}
      securityContext:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- if or $s.env $s.envValueFrom }}
      env:
        {{- range $key, $value := $s.env }}
        - name: {{ $key }}
          value: {{ $value | quote }}
        {{- end }}
        {{- range $key, $ref := $s.envValueFrom }}
        - name: {{ $key }}
          valueFrom:
            {{- toYaml $ref | nindent 12 }}
        {{- end }}
      {{- end }}
      {{- if or $s.envFromConfigMap $s.envFromSecret }}
      envFrom:
        {{- if $s.envFromConfigMap }}
        - configMapRef:
            name: {{ include "generic-chart.fullname" $root }}-config
        {{- end }}
        {{- if $s.envFromSecret }}
        - secretRef:
            name: {{ include "generic-chart.secretName" $root }}
        {{- end }}
      {{- end }}
      {{- if and (eq (.kind | default "") "StatefulSet") $s.persistence }}
      volumeMounts:
        - name: data
          mountPath: {{ required (printf "%s.persistence.mountPath is required" .path) $s.persistence.mountPath }}
      {{- end }}
{{- end }}
