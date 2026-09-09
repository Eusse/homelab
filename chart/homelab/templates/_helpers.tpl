{{/*
Common labels for a given app name.
Usage: {{ include "homelab.labels" (dict "name" "jellyfin") }}
*/}}
{{- define "homelab.labels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/part-of: homelab
app.kubernetes.io/managed-by: {{ .Release.Name | default "Helm" }}
{{- end -}}

{{/*
Name of the Secret holding Infisical universal-auth credentials.
*/}}
{{- define "homelab.infisicalSecretName" -}}
{{- if .Values.infisical.existingCredentialsSecret -}}
{{ .Values.infisical.existingCredentialsSecret }}
{{- else -}}
infisical-credentials
{{- end -}}
{{- end -}}
