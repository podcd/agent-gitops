{{/* One OpenAI-compatible endpoint in front of both ollama and any cloud
     provider, so Cline and Open WebUI are pointed at a single base URL and
     the model choice becomes a routing decision in Git. */}}
apiVersion: v1
kind: Pod
metadata:
  name: litellm
  annotations:
    io.podcd.networks: {{ .Values.network | quote }}
spec:
  restartPolicy: Always
  terminationGracePeriodSeconds: 30
  volumes:
    - name: config
      configMap:
        name: litellm-config
  containers:
    - name: litellm
      image: {{ .Values.images.litellm | quote }}
      command: ["litellm"]
      args:
        - "--config"
        - "/etc/litellm/config.yaml"
        - "--host"
        - "0.0.0.0"
        - "--port"
        - "4000"
      ports:
        - containerPort: 4000
          hostPort: {{ .Values.litellm.hostPort }}
          hostIP: 127.0.0.1
      envFrom:
        - secretRef:
            name: litellm-keys
      volumeMounts:
        - name: config
          mountPath: /etc/litellm
          readOnly: true
      resources:
        limits:
          memory: {{ default "1Gi" .Values.litellm.memoryLimit | quote }}
      {{/* No curl in this image either, so the probe goes through the
           interpreter the proxy itself runs on. */}}
      livenessProbe:
        exec:
          command:
            - /app/.venv/bin/python3
            - -c
            - import urllib.request; urllib.request.urlopen("http://127.0.0.1:4000/health/liveliness", timeout=5)
        timeoutSeconds: 10
        periodSeconds: 30
        failureThreshold: 10
