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
{{- define "sync-in.checksum-env" -}}
{{- if not .Values.syncin.existingEnvSecret -}}
{{- include "sync-in.templates.secret-env" . | sha256sum -}}
{{- else -}}
{{- "" | sha256sum -}}
{{- end -}}
{{- end -}}

{{- define "sync-in.templates.secret-env" -}}
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "sync-in.fullname" . }}-env
  labels:
    {{- include "sync-in.labels" . | nindent 4 }}
    app.kubernetes.io/component: sync-in
stringData:
  environment.yaml: |
  {{- if not .Values.externalDatabase.existingSecret }}
    mysql:
      url: '{{ include "sync-in.mysql-url" . }}'
  {{- end }}
    auth:
      provider: '{{ .Values.auth.provider | default "mysql" }}'
      encryptionKey: '{{ include "sync-in.secret-value" (dict "root" . "value" .Values.auth.encryptionKey "existingSecret" .Values.auth.existingSecret "secretKey" .Values.auth.encryptionKeySecretKey "required" "auth.encryptionKey is required") }}'
      token:
        access:
          secret: '{{ include "sync-in.secret-value" (dict "root" . "value" .Values.auth.token.access.secret "existingSecret" .Values.auth.existingSecret "secretKey" .Values.auth.token.access.secretSecretKey "required" "auth.token.access.secret is required") }}'
        refresh:
          secret: '{{ include "sync-in.secret-value" (dict "root" . "value" .Values.auth.token.refresh.secret "existingSecret" .Values.auth.existingSecret "secretKey" .Values.auth.token.refresh.secretSecretKey "required" "auth.token.refresh.secret is required") }}'
    {{- if eq .Values.auth.provider "oidc" }}
      oidc:
        issuerUrl: '{{ required "auth.oidc.issuerUrl is required when auth.provider is oidc" .Values.auth.oidc.issuerUrl }}'
        clientId: '{{ required "auth.oidc.clientId is required when auth.provider is oidc" .Values.auth.oidc.clientId }}'
        clientSecret: '{{ include "sync-in.secret-value" (dict "root" . "value" .Values.auth.oidc.clientSecret "existingSecret" .Values.auth.existingSecret "secretKey" .Values.auth.oidc.clientSecretSecretKey "required" "auth.oidc.clientSecret is required when auth.provider is oidc") }}'
        redirectUri: '{{ required "auth.oidc.redirectUri is required when auth.provider is oidc" .Values.auth.oidc.redirectUri }}'
        options:
          autoCreateUser: {{ .Values.auth.oidc.options.autoCreateUser }}
          autoCreatePermissions: {{ toJson .Values.auth.oidc.options.autoCreatePermissions }}
        {{- with .Values.auth.oidc.options.adminRoleOrGroup }}
          adminRoleOrGroup: '{{ . }}'
        {{- end }}
          enablePasswordAuth: {{ .Values.auth.oidc.options.enablePasswordAuth }}
          autoSyncAvatar: {{ .Values.auth.oidc.options.autoSyncAvatar }}
          autoRedirect: {{ .Values.auth.oidc.options.autoRedirect }}
          buttonText: '{{ .Values.auth.oidc.options.buttonText }}'
        security:
          scope: '{{ .Values.auth.oidc.security.scope }}'
          supportPKCE: {{ .Values.auth.oidc.security.supportPKCE }}
          allowInsecureRequests: {{ .Values.auth.oidc.security.allowInsecureRequests }}
          tokenEndpointAuthMethod: '{{ .Values.auth.oidc.security.tokenEndpointAuthMethod }}'
          tokenSigningAlg: '{{ .Values.auth.oidc.security.tokenSigningAlg }}'
    {{- end }}
    applications:
      files:
        dataPath: /app/data
        editors:
          collabora:
            enabled: false
    {{- if .Values.onlyoffice.enabled }}
          onlyoffice:
            enabled: true
            secret: '{{ include "sync-in.secret-value" (dict "root" . "value" .Values.onlyoffice.jwtSecret "existingSecret" .Values.onlyoffice.existingSecret "secretKey" .Values.onlyoffice.jwtSecretKey "required" "onlyoffice.jwtSecret is required when onlyoffice.enabled is true") }}'
    {{- else }}
          onlyoffice:
            enabled: false
            secret: 'onlyOfficeSecret'
    {{- end }}
          eurooffice:
            enabled: false
            secret: 'euroOfficeSecret'
{{- end -}}

{{- define "sync-in.checksum-nginx" -}}
{{- printf "%s%s" (include "sync-in.templates.configmap-nginx" .) (include "sync-in.templates.configmap-nginx-onlyoffice" .) | sha256sum -}}
{{- end -}}

{{- define "sync-in.templates.configmap-nginx" -}}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "sync-in.nginx-name" . }}
  labels:
    {{- include "sync-in.labels" . | nindent 4 }}
    app.kubernetes.io/component: nginx
data:
  nginx.conf: |
    map $http_upgrade $connection_upgrade {
        default upgrade;
        ''      close;
    }

    upstream sync_in_server {
        server {{ include "sync-in.fullname" . }}:8080;
        keepalive 32;
    }

    server {
        listen 80;

        charset UTF-8;
        server_tokens off;
        access_log off;
        include /etc/nginx/mime.types;

        sendfile on;
        tcp_nodelay on;
        tcp_nopush on;

        proxy_http_version 1.1;
        chunked_transfer_encoding on;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP  $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_cache_bypass $http_upgrade;
        proxy_redirect off;

        proxy_buffering off;
        proxy_buffers 8 512k;
        proxy_buffer_size 512k;

        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        keepalive_timeout  180  90s;

        proxy_request_buffering off;
        large_client_header_buffers 4 16k;
        client_max_body_size 0;
        client_body_buffer_size 25M;

        location / {
            proxy_pass http://sync_in_server;
        }

        location ~* .(ico|jpg|png|gif|jpeg|swf|woff|svg)$ {
            proxy_pass http://sync_in_server;
            gzip_static on;
            gzip_comp_level 5;
            expires 1d;
            add_header Cache-Control public;
        }

    {{- if .Values.onlyoffice.enabled }}
        include /etc/nginx/onlyoffice.conf;
    {{- end }}

    {{- .Values.nginx.extraServerConfig | nindent 8 }}
    }
{{- end -}}

{{- define "sync-in.templates.configmap-nginx-onlyoffice" -}}
{{- if .Values.onlyoffice.enabled }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "sync-in.nginx-name" . }}-onlyoffice
  labels:
    {{- include "sync-in.labels" . | nindent 4 }}
    app.kubernetes.io/component: nginx
data:
  onlyoffice.conf: |
    location ^~ /onlyoffice/ {
        proxy_pass http://{{ include "sync-in.onlyoffice-name" . }}:80/;
        proxy_set_header X-Real-IP  $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Host $host/onlyoffice;
        proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto;
        proxy_set_header Host $host;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_no_cache 1;
        proxy_cache_bypass 1;
    }
{{- end -}}
{{- end -}}

{{- define "sync-in.checksum-oo" -}}
{{- if .Values.onlyoffice.enabled -}}
{{- include "sync-in.templates.secret-onlyoffice" . | sha256sum -}}
{{- else -}}
{{- "" | sha256sum -}}
{{- end -}}
{{- end -}}

{{- define "sync-in.templates.secret-onlyoffice" -}}
{{- if and .Values.onlyoffice.enabled (not .Values.onlyoffice.existingSecret) }}
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "sync-in.fullname" . }}-onlyoffice
  labels:
    {{- include "sync-in.labels" . | nindent 4 }}
    app.kubernetes.io/component: onlyoffice
stringData:
  JWT_SECRET: {{ include "sync-in.secret-value" (dict "root" . "value" .Values.onlyoffice.jwtSecret "existingSecret" .Values.onlyoffice.existingSecret "secretKey" .Values.onlyoffice.jwtSecretKey "required" "onlyoffice.jwtSecret is required when onlyoffice.enabled is true") | quote }}
{{- end -}}
{{- end -}}

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
