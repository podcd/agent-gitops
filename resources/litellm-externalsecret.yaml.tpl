{{/* Make sure the agent.env file has the Key=Value pairs (default: ~/.config/podcd/agent.env) */}}
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: litellm-keys
spec:
  secretStoreRef:
    name: local
  target:
    name: litellm-keys
  data:
    - secretKey: LITELLM_MASTER_KEY
      remoteRef:
        key: LITELLM_MASTER_KEY
{{- if .Values.litellm.cloud.anthropic }}
    - secretKey: ANTHROPIC_API_KEY
      remoteRef:
        key: ANTHROPIC_API_KEY
{{- end }}
{{- if .Values.litellm.cloud.openai }}
    - secretKey: OPENAI_API_KEY
      remoteRef:
        key: OPENAI_API_KEY
{{- end }}
