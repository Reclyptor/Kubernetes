{{- define "docker-registry.name" -}}
docker-registry
{{- end }}

{{- define "docker-registry.fullname" -}}
{{ .Release.Name }}
{{- end }}

