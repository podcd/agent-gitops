{{/* Single-binary Loki on the filesystem. No object store, no
     microservices, one retention knob. */}}
apiVersion: v1
kind: ConfigMap
metadata:
  name: loki-config
data:
  loki.yaml: |
    auth_enabled: false
    server:
      http_listen_port: 3100
      log_level: warn
    common:
      path_prefix: /loki
      storage:
        filesystem:
          chunks_directory: /loki/chunks
          rules_directory: /loki/rules
      replication_factor: 1
      ring:
        kvstore:
          store: inmemory
    schema_config:
      configs:
        - from: "2024-01-01"
          store: tsdb
          object_store: filesystem
          schema: v13
          index:
            prefix: index_
            period: 24h
    limits_config:
      retention_period: {{ default "168h" .Values.monitoring.loki.retention }}
    compactor:
      working_directory: /loki/compactor
      retention_enabled: true
      delete_request_store: filesystem
    analytics:
      reporting_enabled: false
