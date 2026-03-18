# Lab 012 - Services and Containers

## Introduction

- Many integration tests require real infrastructure - a running database, a message broker, or a cache.
- GitHub Actions supports this through **service containers**: Docker containers that run alongside your job and are accessible to all steps via localhost port mappings.
- You can also run the job itself inside a container, ensuring a consistent environment regardless of the runner's installed tools.

---

## The `services` Block

Service containers are defined at the job level using the `services` key. Each service is a named Docker container started before the job's steps run.

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_PASSWORD: testpassword
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    steps:
      - run: psql -h localhost -U postgres -c "SELECT version();"
        env:
          PGPASSWORD: testpassword
```

---

## PostgreSQL Service

### Full PostgreSQL Integration Test Workflow

```yaml
name: Integration Tests with PostgreSQL

on: [push, pull_request]

jobs:
  integration-tests:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:16-alpine
        env:
          POSTGRES_USER: testuser
          POSTGRES_PASSWORD: testpassword
          POSTGRES_DB: testdb
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: "20"
          cache: "npm"

      - name: Install dependencies
        run: npm ci

      - name: Wait for PostgreSQL
        run: |
          until pg_isready -h localhost -p 5432 -U testuser; do
            echo "Waiting for PostgreSQL..."
            sleep 1
          done
          echo "PostgreSQL is ready!"

      - name: Run database migrations
        env:
          DATABASE_URL: postgresql://testuser:testpassword@localhost:5432/testdb
        run: npm run db:migrate

      - name: Run integration tests
        env:
          DATABASE_URL: postgresql://testuser:testpassword@localhost:5432/testdb
          NODE_ENV: test
        run: npm run test:integration
```

---

## Redis Service

### Redis Cache Integration Test Workflow

```yaml
name: Tests with Redis

on: [push, pull_request]

jobs:
  test-with-redis:
    runs-on: ubuntu-latest

    services:
      redis:
        image: redis:7-alpine
        ports:
          - 6379:6379
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: "20"
          cache: "npm"

      - run: npm ci

      - name: Verify Redis connection
        run: redis-cli -h localhost -p 6379 ping

      - name: Run cache integration tests
        env:
          REDIS_URL: redis://localhost:6379
        run: npm run test:cache
```

---

## Multiple Services Together

### PostgreSQL + Redis + RabbitMQ

```yaml
name: Full Stack Integration Tests

on: [push]

jobs:
  full-integration:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:16-alpine
        env:
          POSTGRES_USER: app
          POSTGRES_PASSWORD: secret
          POSTGRES_DB: appdb
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

      redis:
        image: redis:7-alpine
        ports:
          - 6379:6379
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

      rabbitmq:
        image: rabbitmq:3-management-alpine
        env:
          RABBITMQ_DEFAULT_USER: guest
          RABBITMQ_DEFAULT_PASS: guest
        ports:
          - 5672:5672
          - 15672:15672
        options: >-
          --health-cmd "rabbitmq-diagnostics ping"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 10

      elasticsearch:
        image: elasticsearch:8.11.0
        env:
          discovery.type: single-node
          xpack.security.enabled: "false"
          ES_JAVA_OPTS: "-Xms256m -Xmx256m"
        ports:
          - 9200:9200
        options: >-
          --health-cmd "curl -f http://localhost:9200/_cluster/health"
          --health-interval 15s
          --health-timeout 10s
          --health-retries 10

    steps:
      - uses: actions/checkout@v4

      - name: Wait for all services
        run: |
          echo "Checking PostgreSQL..."
          until pg_isready -h localhost -p 5432; do sleep 1; done

          echo "Checking Redis..."
          until redis-cli -h localhost ping | grep -q PONG; do sleep 1; done

          echo "Checking Elasticsearch..."
          until curl -sf http://localhost:9200/_cluster/health; do sleep 2; done

          echo "All services ready!"

      - name: Run full integration tests
        env:
          DATABASE_URL: postgresql://app:secret@localhost:5432/appdb
          REDIS_URL: redis://localhost:6379
          RABBITMQ_URL: amqp://guest:guest@localhost:5672
          ELASTICSEARCH_URL: http://localhost:9200
        run: npm run test:integration:full
```

---

## Container Networking

Service containers share a Docker network with the runner. Key networking details:

- Services are accessible via **`localhost`** (or `127.0.0.1`) when ports are mapped
- The `ports` mapping uses format `HOST_PORT:CONTAINER_PORT`
- Multiple services can share the network without port conflicts
- Service names become DNS hostnames **within** container-based jobs

```yaml
services:
  db:
    image: postgres:16
    ports:
      - 5432:5432 # localhost:5432 → container:5432
```

---

## Health Check Options

Health checks prevent jobs from starting before services are ready:

```yaml
options: >-
  --health-cmd "pg_isready -U postgres"
  --health-interval 10s
  --health-timeout 5s
  --health-retries 5
  --health-start-period 30s
```

| Option                  | Description                                     |
| ----------------------- | ----------------------------------------------- |
| `--health-cmd`          | Command to run to check health                  |
| `--health-interval`     | Time between health checks                      |
| `--health-timeout`      | Timeout for each check                          |
| `--health-retries`      | Number of consecutive failures before unhealthy |
| `--health-start-period` | Grace period before checks count                |

---

## Running the Job Itself in a Container

Use `container:` to run all steps inside a Docker container instead of directly on the runner VM:

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    container:
      image: node:20-alpine
      env:
        NODE_ENV: test
      volumes:
        - /tmp:/tmp
      options: --cpus 2

    steps:
      - uses: actions/checkout@v4
      - run: node --version
      - run: npm ci
      - run: npm test
```

### Job Container + Services

When using `container:`, services are accessible by their **service name** (not `localhost`):

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    container:
      image: node:20-alpine
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_PASSWORD: secret
        # No ports needed - services are on the Docker network
    steps:
      - run: |
          # Access PostgreSQL via service name, not localhost
          PGPASSWORD=secret psql -h postgres -U postgres -c "SELECT 1;"
```

---

## Python Example with PostgreSQL

```yaml
name: Python Integration Tests

on: [push]

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_USER: pytest
          POSTGRES_PASSWORD: pytest
          POSTGRES_DB: pytest_db
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
          cache: "pip"

      - name: Install dependencies
        run: pip install -r requirements.txt psycopg2-binary

      - name: Run integration tests
        env:
          DATABASE_URL: postgresql://pytest:pytest@localhost:5432/pytest_db
        run: pytest tests/integration/ -v
```

---

## Hands-on

1. Write a workflow job that starts a `postgres:16` service with a health check and connects to it using `psql`:

   ??? success "Solution"
   `bash
    cat > .github/workflows/postgres-service.yml << 'EOF'
    name: Postgres Service
    on: push
    jobs:
      test:
        runs-on: ubuntu-latest
        services:
          postgres:
            image: postgres:16
            env:
              POSTGRES_PASSWORD: testpass
            ports:
              - 5432:5432
            options: >-
              --health-cmd pg_isready
              --health-interval 10s
              --health-timeout 5s
              --health-retries 5
        steps:
          - run: psql -h localhost -U postgres -c "SELECT version();"
            env:
              PGPASSWORD: testpass
    EOF
    `

2. Run a SQL query inside a workflow step to create a table and insert a row into the postgres service:

   ??? success "Solution"
   `bash
    # Add this step after the postgres service is ready:
    # - name: Seed database
    #   env:
    #     PGPASSWORD: testpass
    #   run: |
    psql -h localhost -U postgres -c "CREATE TABLE items (id serial PRIMARY KEY, name text);"
    psql -h localhost -U postgres -c "INSERT INTO items (name) VALUES ('hello');"
    psql -h localhost -U postgres -c "SELECT * FROM items;"
    `

3. Add a `redis:7` service alongside the postgres service and verify both are reachable:

   ??? success "Solution"
   `bash
    cat > .github/workflows/multi-service.yml << 'EOF'
    name: Multi Service
    on: push
    jobs:
      test:
        runs-on: ubuntu-latest
        services:
          postgres:
            image: postgres:16
            env:
              POSTGRES_PASSWORD: testpass
            ports:
              - 5432:5432
            options: >-
              --health-cmd pg_isready
              --health-interval 10s
              --health-timeout 5s
              --health-retries 5
          redis:
            image: redis:7-alpine
            ports:
              - 6379:6379
            options: >-
              --health-cmd "redis-cli ping"
              --health-interval 10s
              --health-timeout 5s
              --health-retries 5
        steps:
          - run: psql -h localhost -U postgres -c "SELECT 1;" && redis-cli -h localhost ping
            env:
              PGPASSWORD: testpass
    EOF
    `

4. Run the entire job inside a `node:20` container and confirm `node --version` reports the correct version:

   ??? success "Solution"
   `bash
    cat > .github/workflows/container-job.yml << 'EOF'
    name: Container Job
    on: push
    jobs:
      build:
        runs-on: ubuntu-latest
        container:
          image: node:20
        steps:
          - uses: actions/checkout@v4
          - run: node --version
          - run: npm ci && npm test
    EOF
    `

5. In a job that uses `container:`, access the postgres service by its service name (not `localhost`) and run a query:

   ??? success "Solution"
   `bash
    cat > .github/workflows/container-with-service.yml << 'EOF'
    name: Container With Service
    on: push
    jobs:
      test:
        runs-on: ubuntu-latest
        container:
          image: node:20
        services:
          postgres:
            image: postgres:16
            env:
              POSTGRES_PASSWORD: testpass
        steps:
          - run: |
              apt-get update -qq && apt-get install -y -qq postgresql-client
              PGPASSWORD=testpass psql -h postgres -U postgres -c "SELECT 'connected via service name';"
    EOF
    `

## Exercises

### Exercise 1 - PostgreSQL Integration Test

Set up a workflow with a PostgreSQL service container and a test that:

1. Connects to the database
2. Creates a table
3. Inserts and queries a row

### Exercise 2 - Redis Session Test

Add a Redis service to a Node.js Express application test. Test that session storage works.

### Exercise 3 - Job in Container

Convert a workflow to run steps inside a `python:3.12-slim` container. Compare the environment with runner-based steps.

### Exercise 4 - Multi-Service Health Check

Create a workflow with three services. Add a dedicated "Wait for Services" step that polls each service until healthy.

### Exercise 5 - Service Networking

Create a job using `container:` and verify that services are accessible by name (not `localhost`).

---

## Summary

- The `services` block defines Docker containers that run alongside job steps and are accessible via `localhost` (or by service name when using `container:`)
- Health check options (`--health-cmd`, `--health-interval`, `--health-retries`) ensure services are ready before steps execute
- Port mappings in the `ports` list expose container ports to the runner's network as `HOST_PORT:CONTAINER_PORT`
- Multiple services (PostgreSQL, Redis, RabbitMQ, Elasticsearch) can coexist in a single job, each with independent health checks
- The `container:` key at the job level runs all steps inside a Docker image, providing a controlled, reproducible environment
- When a job uses `container:`, services are on a shared Docker network and must be addressed by their service name, not `localhost`
- Environment variables passed to services via `env:` configure the container at startup, replacing manual init scripts
