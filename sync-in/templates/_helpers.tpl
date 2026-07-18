{{- define "sync-in.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "sync-in.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "sync-in.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "sync-in.labels" -}}
helm.sh/chart: {{ include "sync-in.chart" . }}
{{ include "sync-in.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "sync-in.selectorLabels" -}}
app.kubernetes.io/name: {{ include "sync-in.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "sync-in.nginx-name" -}}
{{ include "sync-in.fullname" . }}-nginx
{{- end -}}

{{- define "sync-in.onlyoffice-name" -}}
{{ include "sync-in.fullname" . }}-onlyoffice
{{- end -}}

{{- define "sync-in.mariadb-svc" -}}
{{ include "sync-in.fullname" . }}-mariadb
{{- end -}}

{{- define "sync-in.mariadb-username" -}}
root
{{- end -}}

{{- define "sync-in.mariadb-password" -}}
{{- required "mariadb.rootPassword is required when mariadb.enabled is true" .Values.mariadb.rootPassword -}}
{{- end -}}

{{- define "sync-in.mysql-url" -}}
{{- if not .Values.mariadb.enabled -}}
  {{- if .Values.externalDatabase.url -}}
    {{- .Values.externalDatabase.url -}}
  {{- else -}}
    {{- $host := required "externalDatabase.host is required when mariadb.enabled=false and url is not set" .Values.externalDatabase.host -}}
    {{- $port := .Values.externalDatabase.port | default 3306 -}}
    {{- $user := .Values.externalDatabase.user | default "root" -}}
    {{- $pass := required "externalDatabase.password is required when mariadb.enabled=false and url is not set" .Values.externalDatabase.password -}}
    {{- $db := .Values.externalDatabase.database | default "sync_in" -}}
    {{- printf "mysql://%s:%s@%s:%d/%s" $user $pass $host (int $port) $db -}}
  {{- end -}}
{{- else -}}
  mysql://{{ include "sync-in.mariadb-username" . }}:{{ include "sync-in.mariadb-password" . }}@{{ include "sync-in.mariadb-svc" . }}:3306/{{ .Values.mariadb.database }}
{{- end -}}
{{- end -}}

{{/*
Resolve a secret value from an optional existing Kubernetes Secret.
Params (dict):
  root           - the template root context (.)
  value          - the inline chart value (fallback when no existingSecret)
  existingSecret - name of a pre-created Kubernetes Secret
  secretKey      - key within that Secret
  required       - optional: error message to require the value when existingSecret is not set
Returns the decoded secret value when existingSecret+secretKey are provided and the
Secret exists (Helm lookup). Falls back to the inline value. Returns "" during
'helm template' since lookup has no API server available.
*/}}
{{- define "sync-in.secret-value" -}}
{{- $root := index . "root" -}}
{{- $value := index . "value" -}}
{{- $existingSecret := index . "existingSecret" -}}
{{- $secretKey := index . "secretKey" -}}
{{- $requiredMsg := index . "required" -}}
{{- if and $existingSecret $secretKey -}}
  {{- $secret := lookup "v1" "Secret" $root.Release.Namespace $existingSecret -}}
  {{- if and $secret (hasKey $secret.data $secretKey) -}}
    {{- index $secret.data $secretKey | b64dec -}}
  {{- end -}}
{{- else if $requiredMsg -}}
  {{- required $requiredMsg $value -}}
{{- else -}}
  {{- $value -}}
{{- end -}}
{{- end -}}
