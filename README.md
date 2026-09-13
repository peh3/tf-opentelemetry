[ End Users / Traffic Generator ]
                                    │
                                    │ HTTP (Port 8000)
                                    ▼
                     ┌─────────────────────────────┐
                     │   Node 5: Demo Application  │
                     │         (10.0.1.50)         │
                     │  FastAPI + OTel Auto-Agent  │
                     └──────────────┬──────────────┘
                                    │
                                    │ OTLP HTTP (Port 4318)
                                    │ (Traces, Metrics, Logs)
                                    ▼
                     ┌─────────────────────────────┐
                     │  Node 1: OTel Collector     │
                     │         (10.0.1.10)         │
                     │  Batching & Data Routing    │
                     └──────┬───────┬───────┬──────┘
       Traces (OTLP gRPC)   │       │       │   Logs (OTLP HTTP)
             Port 4317      │       │       │   Port 3100
    ┌───────────────────────┘       │       └───────────────────────┐
    ▼                               │ Metrics Scrape (8888/8889)    ▼
┌─────────────────────────┐         ▼                   ┌─────────────────────────┐
│     Node 2: Tempo       │ ┌─────────────────────────┐ │      Node 7: Loki       │
│       (10.0.1.20)       │ │   Node 3: Prometheus    │ │       (10.0.1.70)       │
│   Distributed Tracing   │ │       (10.0.1.30)       │ │      Log Storage        │
│   Query Port: 3200      │ │   Time-Series Database  │ │   Query Port: 3100      │
└───────────┬─────────────┘ │   Query Port: 9090      │ └────────────┬────────────┘
            │               └────────────┬────────────┘              │
            │                            │                           │
            └───────────────────┐        │        ┌──────────────────┘
                                │        │        │
                                ▼        ▼        ▼
                             ┌─────────────────────────┐
                             │     Node 4: Grafana     │
                             │       (10.0.1.40)       │
                             │  Single Pane of Glass   │
                             │  Web UI: Port 3000      │
                             └─────────────────────────┘



# How Jenkins and the Demo App Should Interact

Developer Push
        │
        ▼
┌──────────────────┐
│  Git Repository  │
└───────┬──────────┘
        │ Webhook / Poll
        ▼
┌────────────────────────────────────────┐
│  Node 6: Jenkins Controller            │
│  (10.0.1.60)                           │
│   1. Clones code                       │
│   2. Builds Docker image (demo-app)    │
│   3. Pushes image to Registry / ECR    │
│   4. Triggers remote deploy via SSH    │
└──────────────────┬─────────────────────┘
                   │
                   │ SSH / Docker API
                   ▼
┌────────────────────────────────────────┐
│  Node 5: Demo Application Host         │
│  (10.0.1.50)                           │
│   1. Pulls new image                   │
│   2. Restarts container with OTel env  │
│   3. Serves traffic                    │
└────────────────────────────────────────┘