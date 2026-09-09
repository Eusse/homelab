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

{{/*
A single LAN-facing Ingress rule: <app>.<baseDomain> -> service:port.
Usage: {{ include "homelab.lanIngressRule" (dict "name" "jellyfin" "namespace" $ns
          "ingressClassName" $ic "host" "jellyfin.homelab" "serviceName" "jellyfin-service"
          "servicePort" 8096) }}
*/}}
{{- define "homelab.lanIngressRule" -}}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ .name }}-lan
  namespace: {{ .namespace }}
  labels:
    app.kubernetes.io/name: {{ .name }}
    app.kubernetes.io/part-of: homelab
spec:
  ingressClassName: {{ .ingressClassName }}
  rules:
    - host: {{ .host }}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: {{ .serviceName }}
                port:
                  number: {{ .servicePort }}
{{- end -}}
