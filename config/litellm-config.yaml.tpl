{{/* The proxy's own config file, carried as a ConfigMap so a model-routing
     change is a Git commit and not an edit inside a running container.
     Local models are generated from the same values list ollama pulls
     from, so the two cannot drift apart. */}}
apiVersion: v1
kind: ConfigMap
metadata:
  name: litellm-config
data:
  config.yaml: |
    model_list:
{{- range .Values.ollama.models }}
      - model_name: local/{{ replace ":" "-" . }}
        litellm_params:
          model: ollama_chat/{{ . }}
          api_base: http://ollama:11434
{{- end }}
{{- if .Values.litellm.cloud.anthropic }}
      - model_name: claude-opus-5
        litellm_params:
          model: anthropic/claude-opus-5
          api_key: os.environ/ANTHROPIC_API_KEY
      - model_name: claude-sonnet-5
        litellm_params:
          model: anthropic/claude-sonnet-5
          api_key: os.environ/ANTHROPIC_API_KEY
{{- end }}
{{- if .Values.litellm.cloud.openai }}
      - model_name: gpt-5
        litellm_params:
          model: openai/gpt-5
          api_key: os.environ/OPENAI_API_KEY
{{- end }}

    general_settings:
      master_key: os.environ/LITELLM_MASTER_KEY

    litellm_settings:
      # Local models reject sampling parameters the cloud ones accept.
      drop_params: true
      # Per-request cost, latency and token counts in the proxy log; this
      # is what makes local-vs-cloud comparisons measurable.
      json_logs: true
