{{/* Scrape targets. Everything but litellm lives in the monitoring pod
     itself, so it is reached over localhost; litellm is a pod name on the
     shared network. */}}
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
      evaluation_interval: 15s
    scrape_configs:
      - job_name: prometheus
        static_configs:
          - targets: ["localhost:9090"]
      - job_name: loki
        static_configs:
          - targets: ["localhost:3100"]
      - job_name: gpu
        static_configs:
          - targets: ["localhost:9835"]
      - job_name: podman
        static_configs:
          - targets: ["localhost:9882"]
      - job_name: litellm
        static_configs:
          - targets: ["litellm:{{ .Values.litellm.hostPort }}"]
