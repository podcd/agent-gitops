{{/* Browser chat UI. Talks to ollama directly for model management, and to
     litellm for everything else, so the same model list shows up whether a
     model is local or cloud. */}}
apiVersion: v1
kind: Pod
metadata:
  name: open-webui
  annotations:
    io.podcd.networks: {{ .Values.network | quote }}
spec:
  restartPolicy: Always
  terminationGracePeriodSeconds: 30
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: open-webui-data
  containers:
    - name: open-webui
      image: {{ .Values.images.openWebui | quote }}
      ports:
        - containerPort: 8080
          hostPort: {{ .Values.openWebui.hostPort }}
          hostIP: 127.0.0.1
      env:
        - name: OLLAMA_BASE_URL
          value: "http://ollama:11434"
        - name: OPENAI_API_BASE_URL
          value: "http://litellm:4000/v1"
        - name: WEBUI_AUTH
          value: {{ default false .Values.openWebui.auth | quote }}
        {{/* The proxy's master key doubles as the UI's client key. */}}
        - name: OPENAI_API_KEY
          valueFrom:
            secretKeyRef:
              name: litellm-keys
              key: LITELLM_MASTER_KEY
      volumeMounts:
        - name: data
          mountPath: /app/backend/data
      resources:
        limits:
          memory: {{ default "1Gi" .Values.openWebui.memoryLimit | quote }}
      livenessProbe:
        httpGet:
          path: /health
          port: 8080
        periodSeconds: 30
        failureThreshold: 10
