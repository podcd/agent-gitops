{{/* Only keys for providers actually switched on in values are requested.
     A key named here but missing from agent.env holds litellm back and
     leaves the other workloads alone, so enabling a provider and adding
     its key are one change, not two. */}}
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
