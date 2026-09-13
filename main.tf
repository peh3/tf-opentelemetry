# -----------------------------------------------------------
# 3. Latest Amazon Linux 2023 AMI via SSM
# -----------------------------------------------------------
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# Common init: Installs Docker + enables 2GB swap space for t3.micro survival
locals {
  docker_init = <<-EOF
    #!/bin/bash
    dnf update -y
    dnf install -y docker
    systemctl enable --now docker
    usermod -aG docker ec2-user

    # Enable 2GB swap file to prevent OOM errors on 1GB RAM instances
    if [ ! -f /swapfile ]; then
      dd if=/dev/zero of=/swapfile bs=128M count=16
      chmod 600 /swapfile
      mkswap /swapfile
      swapon /swapfile
      echo '/swapfile swap swap defaults 0 0' >> /etc/fstab
    fi
  EOF
}

# -----------------------------------------------------------
# 4. EC2 Instances (All t3.micro)
# -----------------------------------------------------------

# Node 1: OpenTelemetry Collector (10.0.1.10)
resource "aws_instance" "collector" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  private_ip             = "10.0.1.10"
  vpc_security_group_ids = [aws_security_group.stack_sg.id]
  key_name               = var.key_name != "" ? var.key_name : null

  user_data = <<-EOF
    ${local.docker_init}

    mkdir -p /etc/otel
    cat <<'CONFIG' > /etc/otel/otel-collector-config.yaml
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318

    processors:
      batch:
        timeout: 1s
        send_batch_size: 128

    exporters:
      otlp/tempo:
        endpoint: 10.0.1.20:4317
        tls:
          insecure: true

      prometheus:
        endpoint: 0.0.0.0:8889

      # Export logs directly to Loki via OTLP HTTP
      otlphttp/loki:
        endpoint: "http://10.0.1.70:3100/otlp"
        tls:
          insecure: true

    service:
      telemetry:
        metrics:
          readers:
            - pull:
                exporter:
                  prometheus:
                    host: 0.0.0.0
                    port: 8888
      pipelines:
        traces:
          receivers: [otlp]
          processors: [batch]
          exporters: [otlp/tempo]
        metrics:
          receivers: [otlp]
          processors: [batch]
          exporters: [prometheus]
        logs:
          receivers: [otlp]
          processors: [batch]
          exporters: [otlphttp/loki]
    CONFIG

    docker run -d --name otel-collector --restart unless-stopped \
      -p 4317:4317 -p 4318:4318 -p 8889:8889 -p 8888:8888 \
      -v /etc/otel/otel-collector-config.yaml:/etc/otel-collector-config.yaml:ro \
      otel/opentelemetry-collector-contrib:latest \
      --config=/etc/otel-collector-config.yaml
  EOF

  tags = { Name = "node-otel-collector" }
}

# Node 2: Tempo (10.0.1.20)
resource "aws_instance" "tempo" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  private_ip             = "10.0.1.20"
  vpc_security_group_ids = [aws_security_group.stack_sg.id]
  key_name               = var.key_name != "" ? var.key_name : null

  user_data = <<-EOF
    ${local.docker_init}

    mkdir -p /etc/tempo /var/tempo
    chown -R 10001:10001 /var/tempo

    cat <<'CONFIG' > /etc/tempo/tempo.yaml
    server:
      http_listen_port: 3200

    distributor:
      receivers:
        otlp:
          protocols:
            grpc:
              endpoint: 0.0.0.0:4317

    storage:
      trace:
        backend: local
        local:
          path: /var/tempo/traces
        wal:
          path: /var/tempo/wal
    CONFIG

    docker run -d --name tempo --restart unless-stopped \
      -p 3200:3200 -p 4317:4317 \
      -v /etc/tempo/tempo.yaml:/etc/tempo.yaml:ro \
      -v /var/tempo:/var/tempo \
      grafana/tempo:latest -config.file=/etc/tempo.yaml
  EOF

  tags = { Name = "node-tempo" }
}

# Node 3: Prometheus (10.0.1.30)
resource "aws_instance" "prometheus" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  private_ip             = "10.0.1.30"
  vpc_security_group_ids = [aws_security_group.stack_sg.id]
  key_name               = var.key_name != "" ? var.key_name : null

  user_data = <<-EOF
    ${local.docker_init}

    mkdir -p /etc/prometheus
    cat <<'CONFIG' > /etc/prometheus/prometheus.yml
    global:
      scrape_interval: 10s

    scrape_configs:
      - job_name: "otel-collector"
        static_configs:
          - targets: ["10.0.1.10:8889"]

      - job_name: "otel-collector-internal"
        static_configs:
          - targets: ["10.0.1.10:8888"]
    CONFIG

    docker run -d --name prometheus --restart unless-stopped \
      -p 9090:9090 \
      -v /etc/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro \
      prom/prometheus:latest --config.file=/etc/prometheus/prometheus.yml
  EOF

  tags = { Name = "node-prometheus" }
}

# Node 4: Grafana (10.0.1.40) - Datasources for Prometheus, Tempo, & Loki
resource "aws_instance" "grafana" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  private_ip             = "10.0.1.40"
  vpc_security_group_ids = [aws_security_group.stack_sg.id]
  key_name               = var.key_name != "" ? var.key_name : null

  user_data = <<-EOF
    ${local.docker_init}

    mkdir -p /etc/grafana/provisioning/datasources
    cat <<'CONFIG' > /etc/grafana/provisioning/datasources/datasources.yaml
    apiVersion: 1
    datasources:
      - name: Prometheus
        type: prometheus
        uid: prometheus
        access: proxy
        url: http://10.0.1.30:9090
        isDefault: true

      - name: Loki
        type: loki
        uid: loki
        access: proxy
        url: http://10.0.1.70:3100
        jsonData:
          derivedFields:
            # Parses trace_id from log entries to create a 1-click jump to Tempo
            - matcherRegex: '"trace_id":\s*"([0-9a-fA-F]+)"'
              name: TraceID
              url: '$${__trace.id}'
              datasourceUid: tempo

      - name: Tempo
        type: tempo
        uid: tempo
        access: proxy
        url: http://10.0.1.20:3200
        jsonData:
          tracesToMetrics:
            datasourceUid: prometheus
            tags: [{ key: 'service.name', value: 'service' }]
          tracesToLogsV2:
            datasourceUid: loki
            filterByTraceID: true
            filterBySpanID: false
    CONFIG

    docker run -d --name grafana --restart unless-stopped \
      -p 3000:3000 \
      -e "GF_AUTH_ANONYMOUS_ENABLED=true" \
      -e "GF_AUTH_ANONYMOUS_ORG_ROLE=Admin" \
      -v /etc/grafana/provisioning/datasources:/etc/grafana/provisioning/datasources:ro \
      grafana/grafana:latest
  EOF

  tags = { Name = "node-grafana" }
}

# Node 5: Demo App (10.0.1.50) - With logging auto-instrumentation enabled
resource "aws_instance" "app" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  private_ip             = "10.0.1.50"
  vpc_security_group_ids = [aws_security_group.stack_sg.id]
  key_name               = var.key_name != "" ? var.key_name : null

  user_data = <<-EOF
    ${local.docker_init}

    mkdir -p /app && cd /app

    cat <<'DOCKERFILE' > Dockerfile
    FROM python:3.11-slim
    WORKDIR /app
    RUN pip install fastapi uvicorn opentelemetry-distro opentelemetry-exporter-otlp
    RUN opentelemetry-bootstrap -a install
    COPY main.py .
    ENV OTEL_SERVICE_NAME="ecommerce-api"
    ENV OTEL_EXPORTER_OTLP_ENDPOINT="http://10.0.1.10:4318"
    ENV OTEL_EXPORTER_OTLP_PROTOCOL="http/protobuf"
    ENV OTEL_PYTHON_LOGGING_AUTO_INSTRUMENTATION_ENABLED="true"
    ENV OTEL_LOGS_EXPORTER="otlp"
    CMD ["opentelemetry-instrument", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
    DOCKERFILE

    cat <<'PYAPP' > main.py
    import time
    import random
    import logging
    from fastapi import FastAPI, HTTPException

    logger = logging.getLogger("order-logger")
    logger.setLevel(logging.INFO)

    app = FastAPI()

    @app.get("/order")
    def create_order():
        order_id = random.randint(1000, 9999)
        logger.info(f"Processing incoming order #{order_id}")
        time.sleep(random.uniform(0.1, 0.3))
        logger.info(f"Order #{order_id} processed successfully")
        return {"status": "Order processed", "order_id": order_id}

    @app.get("/error")
    def cause_error():
        logger.error("Simulated database timeout occurred while updating inventory")
        raise HTTPException(status_code=500, detail="Inventory timeout")
    PYAPP

    docker build -t demo-app:latest .
    docker run -d --name demo-app --restart unless-stopped -p 8000:8000 demo-app:latest
  EOF

  tags = { Name = "node-demo-app" }
}

# Node 6: Jenkins Controller (10.0.1.60)
resource "aws_instance" "jenkins" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  private_ip             = "10.0.1.60"
  vpc_security_group_ids = [aws_security_group.stack_sg.id]
  key_name               = var.key_name != "" ? var.key_name : null

  user_data = <<-EOF
    ${local.docker_init}

    mkdir -p /var/jenkins_home
    chown -R 1000:1000 /var/jenkins_home

    docker run -d --name jenkins --restart unless-stopped \
      -p 8080:8080 -p 50000:50000 \
      -e JAVA_OPTS="-Xms256m -Xmx512m -XX:+UseG1GC" \
      -v /var/jenkins_home:/var/jenkins_home \
      -v /var/run/docker.sock:/var/run/docker.sock \
      jenkins/jenkins:lts-jdk17
  EOF

  tags = { Name = "node-jenkins" }
}

# Node 7: Dedicated Grafana Loki Instance (10.0.1.70)
resource "aws_instance" "loki" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  private_ip             = "10.0.1.70"
  vpc_security_group_ids = [aws_security_group.stack_sg.id]
  key_name               = var.key_name != "" ? var.key_name : null

  user_data = <<-EOF
    ${local.docker_init}

    mkdir -p /etc/loki /var/loki
    chown -R 10001:10001 /var/loki

    cat <<'CONFIG' > /etc/loki/loki-config.yaml
    auth_enabled: false

    server:
      http_listen_port: 3100

    common:
      ring:
        instance_addr: 127.0.0.1
        kvstore:
          store: inmemory
      replication_factor: 1
      path_prefix: /var/loki

    schema_config:
      configs:
        - from: 2024-01-01
          store: tsdb
          object_store: filesystem
          schema: v13
          index:
            prefix: index_
            period: 24h

    storage_config:
      filesystem:
        directory: /var/loki/chunks

    limits_config:
      allow_structured_metadata: true
      volume_enabled: true
    CONFIG

    docker run -d --name loki --restart unless-stopped \
      -p 3100:3100 \
      -v /etc/loki/loki-config.yaml:/etc/loki/loki-config.yaml:ro \
      -v /var/loki:/var/loki \
      grafana/loki:latest -config.file=/etc/loki/loki-config.yaml
  EOF

  tags = { Name = "node-loki" }
}