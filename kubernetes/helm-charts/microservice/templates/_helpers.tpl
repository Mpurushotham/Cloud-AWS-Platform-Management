{{- define "microservice.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "microservice.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{ include "microservice.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "microservice.selectorLabels" -}}
app.kubernetes.io/name: {{ include "microservice.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
