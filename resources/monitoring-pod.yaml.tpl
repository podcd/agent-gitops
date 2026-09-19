{{/* One pod, six containers, all on localhost to each other. Grafana is the
     only thing meant to be looked at; Prometheus gets a host port too since
     its query page is the quickest way to check a scrape target. Every
     container that touches something owned by this user on the host - the
     journal, the podman socket, the named volumes - runs as root inside
     the container, which rootless podman maps back to this user. */}}
apiVersion: v1
kind: Pod
metadata:
  name: monitoring
  annotations:
    io.podcd.networks: {{ .Values.network | quote }}
spec:
  restartPolicy: Always
  terminationGracePeriodSeconds: 30
  volumes:
    - name: grafana-data
      persistentVolumeClaim:
        claimName: grafana-data
    - name: prometheus-data
      persistentVolumeClaim:
        claimName: prometheus-data
    - name: loki-data
      persistentVolumeClaim:
        claimName: loki-data
    {{/* Alloy's journal cursor. Without it a restart replays the last
         max_age of journal, and Loki refuses every line older than what
         it already holds for that stream: "entry too far behind". */}}
    - name: alloy-data
      persistentVolumeClaim:
        claimName: alloy-data
    - name: grafana-datasources
      configMap:
        name: grafana-datasources
    - name: grafana-dashboards
      configMap:
        name: grafana-dashboards
    - name: prometheus-config
      configMap:
        name: prometheus-config
    - name: loki-config
      configMap:
        name: loki-config
    - name: alloy-config
      configMap:
        name: alloy-config
    - name: journal
      hostPath:
        path: /var/log/journal
        type: Directory
    - name: machine-id
      hostPath:
        path: /etc/machine-id
        type: File
    - name: podman-sock
      hostPath:
        path: /run/user/{{ required "values: hostUid is needed to find the podman socket" .Values.hostUid }}/podman/podman.sock
        type: Socket
{{- if eq .Values.gpu.mode "wsl" }}
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
    - name: grafana
      image: {{ .Values.images.grafana | quote }}
      securityContext:
        runAsUser: 0
      ports:
        - containerPort: 3000
          hostPort: {{ .Values.monitoring.grafana.hostPort }}
          hostIP: 127.0.0.1
      env:
        - name: GF_ANALYTICS_REPORTING_ENABLED
          value: "false"
        - name: GF_ANALYTICS_CHECK_FOR_UPDATES
          value: "false"
        - name: GF_NEWS_NEWS_FEED_ENABLED
          value: "false"
{{- if .Values.monitoring.grafana.anonymousAdmin }}
        - name: GF_AUTH_ANONYMOUS_ENABLED
          value: "true"
        - name: GF_AUTH_ANONYMOUS_ORG_ROLE
          value: Admin
        - name: GF_AUTH_DISABLE_LOGIN_FORM
          value: "true"
{{- end }}
      volumeMounts:
        - name: grafana-data
          mountPath: /var/lib/grafana
        - name: grafana-datasources
          mountPath: /etc/grafana/provisioning/datasources
          readOnly: true
        - name: grafana-dashboards
          mountPath: /etc/grafana/provisioning/dashboards
          readOnly: true
      resources:
        limits:
          memory: 512Mi
      livenessProbe:
        httpGet:
          path: /api/health
          port: 3000
        timeoutSeconds: 10
        periodSeconds: 30
        failureThreshold: 10

    - name: prometheus
      image: {{ .Values.images.prometheus | quote }}
      securityContext:
        runAsUser: 0
      args:
        - --config.file=/etc/prometheus/prometheus.yml
        - --storage.tsdb.path=/prometheus
        - --storage.tsdb.retention.time={{ default "15d" .Values.monitoring.prometheus.retention }}
        - --web.enable-lifecycle
      ports:
        - containerPort: 9090
          hostPort: {{ .Values.monitoring.prometheus.hostPort }}
          hostIP: 127.0.0.1
      volumeMounts:
        - name: prometheus-data
          mountPath: /prometheus
        - name: prometheus-config
          mountPath: /etc/prometheus
          readOnly: true
      resources:
        limits:
          memory: 512Mi

    - name: loki
      image: {{ .Values.images.loki | quote }}
      securityContext:
        runAsUser: 0
      args:
        - -config.file=/etc/loki/loki.yaml
      volumeMounts:
        - name: loki-data
          mountPath: /loki
        - name: loki-config
          mountPath: /etc/loki
          readOnly: true
      resources:
        limits:
          memory: 512Mi

    - name: alloy
      image: {{ .Values.images.alloy | quote }}
      {{/* Root inside the container is this user outside it, which is the
           only identity the journal's ACL grants read to. */}}
      securityContext:
        runAsUser: 0
      args:
        - run
        - --storage.path=/var/lib/alloy
        - --server.http.listen-addr=127.0.0.1:12345
        - /etc/alloy/config.alloy
      volumeMounts:
        - name: alloy-data
          mountPath: /var/lib/alloy
        - name: alloy-config
          mountPath: /etc/alloy
          readOnly: true
        - name: journal
          mountPath: /var/log/journal
          readOnly: true
        - name: machine-id
          mountPath: /etc/machine-id
          readOnly: true
      resources:
        limits:
          memory: 256Mi

    - name: gpu-exporter
      image: {{ .Values.images.gpuExporter | quote }}
      args:
        - --web.listen-address=:9835
{{- if eq .Values.gpu.mode "wsl" }}
        - --nvidia-smi-command=/usr/lib/wsl/lib/nvidia-smi
      env:
        - name: LD_LIBRARY_PATH
          value: /usr/lib/wsl/lib
      volumeMounts:
        - name: wsl
          mountPath: /usr/lib/wsl
          readOnly: true
        - name: dxg
          mountPath: /dev/dxg
{{- end }}
      resources:
        limits:
          memory: 64Mi
{{- if eq .Values.gpu.mode "cdi" }}
          "nvidia.com/gpu=all": 1
{{- end }}

    - name: podman-exporter
      image: {{ .Values.images.podmanExporter | quote }}
      {{/* The socket is owned by this user; the image's own unprivileged
           uid maps into the subordinate range and gets EACCES. */}}
      securityContext:
        runAsUser: 0
      args:
        - --collector.enable-all
        - --web.listen-address=:9882
      env:
        - name: CONTAINER_HOST
          value: unix:///run/podman/podman.sock
      volumeMounts:
        - name: podman-sock
          mountPath: /run/podman/podman.sock
      resources:
        limits:
          memory: 128Mi
