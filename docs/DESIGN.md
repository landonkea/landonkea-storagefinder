# landonkea-storagefinder — Design & Workflow

## High-Level Overview

```mermaid
graph TB
    subgraph "Rails 8 App"
        A[Puma Web Server] --> B[Controllers]
        B --> C[Models]
        C --> D[(SQLite)]
        B --> E[Action Cable]
        E --> F[WebSocket]
    end

    subgraph "Background Jobs"
        G[Solid Queue] --> H[Crawl Job]
        H --> I[Playwright Browser]
        I --> J[Scrape Websites]
        J --> K[Store Results]
    end

    subgraph "Deployment"
        L[Kamal] --> M[Docker Container]
        M --> N[LAN Server]
    end
```

## Crawl Workflow

```mermaid
sequenceDiagram
    participant U as User
    participant W as Web UI
    participant J as Background Job
    participant P as Playwright
    participant S as Storage Site

    U->>W: Click "Run Crawl"
    W->>J: Enqueue CrawlJob
    J->>P: Launch browser
    P->>S: Navigate to site
    S-->>P: Render page
    P->>P: Extract pricing data
    P-->>J: Listings found
    J->>J: Store in SQLite
    J->>W: Update dashboard via Action Cable
    W-->>U: Real-time results
```

## Alert Flow

```mermaid
flowchart TD
    A[New crawl completes] --> B[Compare prices]
    B --> C{Price drop or deal?}
    C -->|Yes| D[Send Discord webhook]
    C -->|No| E[Log result]
    D --> F[User notified]
```

## File Relationships

| File | Purpose | Used By |
|------|---------|---------|
| `app/controllers/` | HTTP handlers | Puma |
| `app/models/` | Business logic | Controllers |
| `app/jobs/` | Background jobs | Solid Queue |
| `app/channels/` | WebSocket updates | Action Cable |
| `config/deploy.yml` | Kamal config | Deployment |
| `db/` | SQLite schema | Models |

## draw.io

[Open in draw.io](https://app.diagrams.net/#RStorageFinder%20architecture)
