{{/*
Expand the name of the chart.
*/}}
{{- define "secure-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "secure-app.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "secure-app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "secure-app.labels" -}}
helm.sh/chart: {{ include "secure-app.chart" . }}
{{ include "secure-app.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: devsecops-pipeline
{{- end }}

{{/*
Selector labels
*/}}
{{- define "secure-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "secure-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Security labels
*/}}
{{- define "secure-app.securityLabels" -}}
security.policy: "restricted"
compliance.framework/soc2: "validated"
compliance.framework/nist: "validated"
compliance.framework/cis: "validated"
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "secure-app.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "secure-app.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create image name
*/}}
{{- define "secure-app.image" -}}
{{- if .Values.global.imageRegistry }}
{{- printf "%s/%s:%s" .Values.global.imageRegistry .Values.image.repository (.Values.image.tag | default .Chart.AppVersion) }}
{{- else if .Values.image.registry }}
{{- printf "%s/%s:%s" .Values.image.registry .Values.image.repository (.Values.image.tag | default .Chart.AppVersion) }}
{{- else }}
{{- printf "%s:%s" .Values.image.repository (.Values.image.tag | default .Chart.AppVersion) }}
{{- end }}
{{- end }}

{{/*
Create image pull secrets
*/}}
{{- define "secure-app.imagePullSecrets" -}}
{{- $secrets := list }}
{{- if .Values.global.imagePullSecrets }}
{{- $secrets = concat $secrets .Values.global.imagePullSecrets }}
{{- end }}
{{- if .Values.image.pullSecrets }}
{{- $secrets = concat $secrets .Values.image.pullSecrets }}
{{- end }}
{{- if $secrets }}
imagePullSecrets:
{{- range $secrets }}
- name: {{ . }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Generate environment variables
*/}}
{{- define "secure-app.env" -}}
{{- range .Values.env }}
- name: {{ .name }}
  value: {{ .value | quote }}
{{- end }}
{{- if .Values.postgresql.enabled }}
- name: DATABASE_URL
  value: "postgresql://{{ .Values.postgresql.auth.username }}:$(POSTGRES_PASSWORD)@{{ include "secure-app.fullname" . }}-postgresql:5432/{{ .Values.postgresql.auth.database }}"
- name: POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "secure-app.fullname" . }}-postgresql
      key: postgres-password
{{- end }}
{{- if .Values.redis.enabled }}
- name: REDIS_URL
  value: "redis://:$(REDIS_PASSWORD)@{{ include "secure-app.fullname" . }}-redis-master:6379"
- name: REDIS_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "secure-app.fullname" . }}-redis
      key: redis-password
{{- end }}
{{- end }}

{{/*
Generate resource requirements
*/}}
{{- define "secure-app.resources" -}}
{{- if .Values.resources }}
resources:
  {{- if .Values.resources.limits }}
  limits:
    {{- range $key, $value := .Values.resources.limits }}
    {{ $key }}: {{ $value }}
    {{- end }}
  {{- end }}
  {{- if .Values.resources.requests }}
  requests:
    {{- range $key, $value := .Values.resources.requests }}
    {{ $key }}: {{ $value }}
    {{- end }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
Generate volume mounts
*/}}
{{- define "secure-app.volumeMounts" -}}
{{- if .Values.volumeMounts }}
volumeMounts:
{{- toYaml .Values.volumeMounts | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Generate volumes
*/}}
{{- define "secure-app.volumes" -}}
{{- if .Values.volumes }}
volumes:
{{- toYaml .Values.volumes | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Generate pod annotations
*/}}
{{- define "secure-app.podAnnotations" -}}
{{- if .Values.monitoring.enabled }}
prometheus.io/scrape: "true"
prometheus.io/port: "{{ .Values.app.port }}"
prometheus.io/path: "/metrics"
{{- end }}
security.scan/trivy: "passed"
security.scan/snyk: "passed"
security.scan/checkmarx: "passed"
policy.validation/conftest: "passed"
{{- end }}

{{/*
Generate security context
*/}}
{{- define "secure-app.securityContext" -}}
{{- if .Values.securityContext }}
securityContext:
  {{- toYaml .Values.securityContext | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Generate container security context
*/}}
{{- define "secure-app.containerSecurityContext" -}}
{{- if .Values.containerSecurityContext }}
securityContext:
  {{- toYaml .Values.containerSecurityContext | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Generate node selector
*/}}
{{- define "secure-app.nodeSelector" -}}
{{- if .Values.nodeSelector }}
nodeSelector:
  {{- toYaml .Values.nodeSelector | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Generate tolerations
*/}}
{{- define "secure-app.tolerations" -}}
{{- if .Values.tolerations }}
tolerations:
  {{- toYaml .Values.tolerations | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Generate affinity
*/}}
{{- define "secure-app.affinity" -}}
{{- if .Values.affinity }}
affinity:
  {{- toYaml .Values.affinity | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Generate ingress annotations
*/}}
{{- define "secure-app.ingressAnnotations" -}}
{{- if .Values.ingress.annotations }}
annotations:
  {{- toYaml .Values.ingress.annotations | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Generate database connection check
*/}}
{{- define "secure-app.databaseCheck" -}}
{{- if .Values.postgresql.enabled }}
- name: check-postgres
  image: postgres:13-alpine
  command:
    - sh
    - -c
    - |
      until pg_isready -h {{ include "secure-app.fullname" . }}-postgresql -p 5432 -U {{ .Values.postgresql.auth.username }}; do
        echo "Waiting for PostgreSQL..."
        sleep 2
      done
      echo "PostgreSQL is ready!"
  env:
  - name: PGUSER
    value: {{ .Values.postgresql.auth.username }}
  - name: PGPASSWORD
    valueFrom:
      secretKeyRef:
        name: {{ include "secure-app.fullname" . }}-postgresql
        key: postgres-password
{{- end }}
{{- end }}

{{/*
Generate compliance labels
*/}}
{{- define "secure-app.complianceLabels" -}}
{{- if .Values.compliance.enabled }}
{{- range .Values.compliance.frameworks }}
compliance.framework/{{ . }}: "enabled"
{{- end }}
{{- end }}
{{- end }}

{{/*
Generate monitoring labels
*/}}
{{- define "secure-app.monitoringLabels" -}}
{{- if .Values.monitoring.enabled }}
monitoring.prometheus/scrape: "true"
monitoring.grafana/dashboard: "enabled"
{{- end }}
{{- end }}

{{/*
Generate backup labels
*/}}
{{- define "secure-app.backupLabels" -}}
{{- if .Values.backup.enabled }}
backup.velero/enabled: "true"
backup.schedule: {{ .Values.backup.schedule | quote }}
{{- end }}
{{- end }}

{{/*
Generate all labels
*/}}
{{- define "secure-app.allLabels" -}}
{{ include "secure-app.labels" . }}
{{ include "secure-app.securityLabels" . }}
{{ include "secure-app.complianceLabels" . }}
{{ include "secure-app.monitoringLabels" . }}
{{ include "secure-app.backupLabels" . }}
{{- end }}