# tf-opentelemetry

[ User Traffic ]
         │
         ▼
 ┌────────────────────────────────────────────────────────┐
 │ Node 5: Demo Application (10.0.1.50)                   │
 │  • FastAPI HTTP Web Server                             │
 │  • OpenTelemetry SDK (Auto-Instrumentation)            │
 └───────────────────────┬────────────────────────────────┘
                         │ 
                         │ OTLP (OpenTelemetry Protocol)
                         │ HTTP / protobuf via Port 4318
                         ▼
 ┌────────────────────────────────────────────────────────┐
 │ Node 1: OpenTelemetry Collector (10.0.1.10)            │
 │  • Port 4317 (gRPC) & 4318 (HTTP): Ingestion Receivers │
 │  • Batch Processor: Queues and batches records         │
 │  • Exporters: Splits streams into Traces & Metrics     │
 │  • Port 8888: Internal Collector Telemetry / Health    │
 │  • Port 8889: Scrape endpoint for App Metrics          │
 └──────────────┬──────────────────────────┬──────────────┘
                │                          │
   Traces (OTLP)│:4317                     │ Scrape :8889 & :8888
                ▼                          ▼
 ┌──────────────────────────┐   ┌──────────────────────────┐
 │ Node 2: Tempo (10.0.1.20)│   │ Node 3: Prometheus       │
 │  • Distributed Tracing   │   │         (10.0.1.30)      │
 │  • Stores span trees     │   │  • Time-Series Database  │
 │  • Port 3200: Query HTTP │   │  • Port 9090: Query HTTP │
 └──────────────┬───────────┘   └──────────┬───────────────┘
                │                          │
                │ Queries                  │ Queries
                └───────────┬──────────────┘
                            │
                            ▼
 ┌────────────────────────────────────────────────────────┐
 │ Node 4: Grafana (10.0.1.40)                            │
 │  • Unified Single Pane of Glass                        │
 │  • Visualizes Prometheus counters and rates            │
 │  • Renders Tempo trace waterfall graphs                │
 │  • Correlates metrics to traces                        │
 └────────────────────────────────────────────────────────┘