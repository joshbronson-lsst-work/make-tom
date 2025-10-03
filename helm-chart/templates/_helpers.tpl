{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "tom-deploy.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "tom-deploy.fullname" -}}
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

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "tom-deploy.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Generate the tom-deploy main deploy url
*/}}
{{- define "tom-deploy.mainDeployUrl" -}}
{{- $ingressClass := index .Values.ingress.annotations "kubernetes.io/ingress.class" | quote -}}
{{- $hosts := first .Values.ingress.hosts -}}
{{- $host := pluck "host" $hosts | first -}}
{{- if contains "nginx-ingress-public" $ingressClass -}}
{{- printf "https://%s" $host -}}
{{- else -}}
{{- printf "http://%s" $host -}}
{{- end -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "tom-deploy.labels" -}}
app.kubernetes.io/name: {{ include "tom-deploy.name" . }}
helm.sh/chart: {{ include "tom-deploy.chart" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "tom-deploy.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{ default (include "tom-deploy.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Generate the postgres DB hostname
*/}}
{{- define "tom-deploy.dbhost" -}}
{{- if .Values.database.host -}}
{{- .Values.database.host | quote | trimAll '"' -}}
{{- else -}}
{{- $cn := default (include "tom-deploy.fullname" .) .Values.cnpg.clusterName -}}
{{- printf "%s-rw" $cn -}}
{{- end -}}
{{- end -}}

{{/*
Create the environment variables for configuration of this project. They are
repeated in a bunch of places, so to keep from repeating ourselves, we'll
build it here and use it everywhere.
*/}}
{{- define "tom-deploy.extraEnv" -}}
- name: HOME
  value: "/tmp"
- name: TOM_DEMO_DEBUG
  value: {{ .Values.djangoDebug | toString | lower | title | quote }}
- name: USE_WHITENOISE
  value: {{ .Values.useWhitenoise | toString | lower | title | quote }}
- name: CSRF_TRUSTED_ORIGINS
  value: {{ join "," .Values.csrf_trusted_origins | quote }}
- name: ALLOWED_HOSTS
  value: {{ join "," .Values.allowedHosts | quote }}
- name: GS_BUCKET_NAME
  value: {{ .Values.gsBucketName | default "" | quote }}
{{- end }}

{{/*
Define shared database environment variables
*/}}
{{- define "tom-deploy.backendEnv" -}}
- name: DB_HOST
  value: {{ include "tom-deploy.dbhost" . | quote }}
{{- if .Values.database.existingSecret }}
- name: DB_NAME
  valueFrom:
    secretKeyRef:
      name: {{ .Values.database.existingSecret | quote }}
      key: {{ .Values.database.secretKeys.name | default "dbname" | quote }}
- name: DB_USER
  valueFrom:
    secretKeyRef:
      name: {{ .Values.database.existingSecret | quote }}
      key: {{ .Values.database.secretKeys.user | default "username" | quote }}
- name: DB_PASS
  valueFrom:
    secretKeyRef:
      name: {{ .Values.database.existingSecret | quote }}
      key: {{ .Values.database.secretKeys.password | default "password" | quote }}
{{- else }}
- name: DB_NAME
  value: {{ .Values.database.name | default "app" | quote }}
- name: DB_USER
  value: {{ .Values.database.user | default "app" | quote }}
- name: DB_PASS
  value: {{ .Values.database.password | default "" | quote }}
{{- end }}
- name: DB_PORT
  value: {{ .Values.database.port | default "5432" | quote }}
- name: SECRET_KEY
  value: {{ .Values.secretKey | quote }}
{{- end -}}
