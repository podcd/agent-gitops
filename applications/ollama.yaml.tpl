{{/* The local inference runtime. Serves an OpenAI-compatible API on
     11434 and holds the model weights in a podman named volume, so a pod
     restart does not re-download several GB. */}}
apiVersion: v1
kind: Pod
metadata:
  name: ollama
  annotations:
    io.podcd.networks: {{ .Values.network | quote }}
spec:
  restartPolicy: Always
  terminationGracePeriodSeconds: 30
  volumes:
    - name: models
      persistentVolumeClaim:
        claimName: ollama-models
{{- if eq .Values.gpu.mode "wsl" }}
    {{/* The whole tree, not just lib/: libnvidia-ml.so.1 reaches through
         libdxcore into the Windows driver store under drivers/, and
         nvidia-smi reports "Driver Not Loaded" without it. */}}
    - name: wsl
      hostPath:
        path: /usr/lib/wsl
        type: Directory
    - name: dxg
      hostPath:
        path: /dev/dxg
        type: CharDevice
{{- end }}
  containers:
    - name: ollama
      image: {{ .Values.images.ollama | quote }}
      ports:
        - containerPort: 11434
          hostPort: {{ .Values.ollama.hostPort }}
          hostIP: 127.0.0.1
      env:
        - name: OLLAMA_HOST
          value: "0.0.0.0:11434"
        - name: OLLAMA_MODELS
          value: /models
        - name: OLLAMA_KEEP_ALIVE
          value: {{ default "30m" .Values.ollama.keepAlive | quote }}
        - name: OLLAMA_CONTEXT_LENGTH
          value: {{ default 8192 .Values.ollama.contextLength | quote }}
        - name: OLLAMA_MAX_LOADED_MODELS
          value: {{ default 1 .Values.ollama.maxLoadedModels | quote }}
{{- if eq .Values.gpu.mode "wsl" }}
        {{/* WSL2 puts the CUDA driver stubs here, not in the usual paths. */}}
        - name: LD_LIBRARY_PATH
          value: /usr/lib/wsl/lib
{{- end }}
      volumeMounts:
        - name: models
          mountPath: /models
{{- if eq .Values.gpu.mode "wsl" }}
        - name: wsl
          mountPath: /usr/lib/wsl
          readOnly: true
        - name: dxg
          mountPath: /dev/dxg
{{- end }}
      resources:
        limits:
          memory: {{ default "8Gi" .Values.ollama.memoryLimit | quote }}
{{- if eq .Values.gpu.mode "cdi" }}
          {{/* Needs nvidia-container-toolkit and /etc/cdi/nvidia.yaml;
               run bootstrap/nvidia-cdi.sh before switching to this mode. */}}
          "nvidia.com/gpu=all": 1
{{- end }}
      livenessProbe:
        httpGet:
          path: /api/version
          port: 11434
        periodSeconds: 30
        failureThreshold: 10
    {{/* Declarative model management: the list in values is the desired
         state. `ollama pull` is a client call against the server in this
         same pod, so this container needs no volume of its own. It sleeps
         rather than exits, because restartPolicy Always would otherwise
         restart it forever. */}}
    - name: model-puller
      image: {{ .Values.images.ollama | quote }}
      command: ["/bin/sh", "-c"]
      args:
        - |
          set -eu
          until /bin/ollama list >/dev/null 2>&1; do sleep 2; done
{{- range .Values.ollama.models }}
          echo "pulling {{ . }}"
          /bin/ollama pull {{ . | quote }}
{{- end }}
          echo "models ready"
          exec sleep infinity
      env:
        - name: OLLAMA_HOST
          value: "http://127.0.0.1:11434"
      resources:
        limits:
          memory: 512Mi
