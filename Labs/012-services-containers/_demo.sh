#!/usr/bin/env bash
set -euo pipefail

ROOT_FOLDER=$(git rev-parse --show-toplevel)
source "$ROOT_FOLDER/_utils/common.sh"

# =============================================================================
# Lab 012 - Services and Containers Demo
# Demonstrates: workflow YAML with PostgreSQL and Redis services,
#               health checks, container networking, job containers
# =============================================================================

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW_DIR="$LAB_DIR/workflow-examples"

print_header "Lab 012 - Services and Containers"
print_info "This demo generates workflow YAML files demonstrating service containers."

mkdir -p "$WORKFLOW_DIR"

# -----------------------------------------------------------------------------
# 1. PostgreSQL + Redis services workflow
# -----------------------------------------------------------------------------
print_step "Creating PostgreSQL + Redis services workflow..."

cat >"$WORKFLOW_DIR/postgres-redis-services.yml" <<'EOF'
name: Integration Tests with PostgreSQL and Redis

on:
  push:
    branches: [main, develop]
  pull_request:

jobs:
  integration-tests:
    name: Integration Tests
    runs-on: ubuntu-latest

    services:
      # PostgreSQL service
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
          --health-start-period 10s

      # Redis service
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
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'

      - name: Install dependencies
        run: npm ci

      - name: Verify PostgreSQL is ready
        run: |
          echo "Testing PostgreSQL connection..."
          PGPASSWORD=testpassword psql \
            -h localhost \
            -U testuser \
            -d testdb \
            -c "SELECT version();"
          echo "PostgreSQL is ready!"

      - name: Verify Redis is ready
        run: |
          echo "Testing Redis connection..."
          redis-cli -h localhost -p 6379 ping
          redis-cli -h localhost -p 6379 set test-key "hello"
          redis-cli -h localhost -p 6379 get test-key
          echo "Redis is ready!"

      - name: Run database migrations
        env:
          DATABASE_URL: postgresql://testuser:testpassword@localhost:5432/testdb
        run: npm run db:migrate

      - name: Run integration tests
        env:
          DATABASE_URL: postgresql://testuser:testpassword@localhost:5432/testdb
          REDIS_URL: redis://localhost:6379
          NODE_ENV: test
        run: npm run test:integration

      - name: Upload test results
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: integration-test-results
          path: test-results/
          retention-days: 14
EOF

print_success "Created: $WORKFLOW_DIR/postgres-redis-services.yml"

# -----------------------------------------------------------------------------
# 2. Full stack services workflow
# -----------------------------------------------------------------------------
print_step "Creating full-stack multi-service workflow..."

cat >"$WORKFLOW_DIR/full-stack-services.yml" <<'EOF'
name: Full Stack Services Integration

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
          --health-interval 5s
          --health-timeout 3s
          --health-retries 10

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

    steps:
      - uses: actions/checkout@v4

      - name: Wait for all services to be healthy
        run: |
          echo "=== Service Health Check ==="

          echo "Checking PostgreSQL..."
          timeout 60 bash -c 'until pg_isready -h localhost -p 5432; do sleep 2; done'
          echo "  PostgreSQL: READY"

          echo "Checking Redis..."
          timeout 60 bash -c 'until redis-cli -h localhost ping | grep -q PONG; do sleep 2; done'
          echo "  Redis: READY"

          echo "Checking RabbitMQ..."
          timeout 120 bash -c 'until curl -sf http://localhost:15672/api/overview -u guest:guest > /dev/null 2>&1; do sleep 3; done'
          echo "  RabbitMQ: READY"

          echo "All services are ready!"

      - name: Run integration tests
        env:
          DATABASE_URL: postgresql://app:secret@localhost:5432/appdb
          REDIS_URL: redis://localhost:6379
          RABBITMQ_URL: amqp://guest:guest@localhost:5672
        run: npm run test:integration:full
EOF

print_success "Created: $WORKFLOW_DIR/full-stack-services.yml"

# -----------------------------------------------------------------------------
# 3. Job container workflow
# -----------------------------------------------------------------------------
print_step "Creating job-in-container workflow..."

cat >"$WORKFLOW_DIR/job-container.yml" <<'EOF'
name: Job Running Inside Container

on: [push]

jobs:
  # Run entire job inside a specific Docker image
  test-in-container:
    name: Tests in Node.js Container
    runs-on: ubuntu-latest
    container:
      image: node:20-alpine
      env:
        NODE_ENV: test
      options: --cpus 2 --memory 2g

    steps:
      - uses: actions/checkout@v4

      - name: Verify container environment
        run: |
          echo "Node version: $(node --version)"
          echo "NPM version: $(npm --version)"
          echo "OS: $(uname -a)"
          echo "User: $(whoami)"

      - name: Install dependencies
        run: npm ci

      - name: Run tests
        run: npm test

  # Job container + services - note: services use hostname, not localhost
  test-with-db-in-container:
    name: Tests in Container with Database
    runs-on: ubuntu-latest
    container:
      image: node:20-alpine   # Job runs inside this container

    services:
      # When using container:, services are on a shared Docker network
      # Access them by SERVICE NAME, not localhost
      postgres:
        image: postgres:16-alpine
        env:
          POSTGRES_USER: app
          POSTGRES_PASSWORD: secret
          POSTGRES_DB: appdb
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
      redis:
        image: redis:7-alpine
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 5s
          --health-timeout 3s
          --health-retries 10

    steps:
      - uses: actions/checkout@v4

      - name: Install postgresql client tools
        run: apk add --no-cache postgresql-client redis

      - name: Verify DB connection via service hostname
        run: |
          # Note: use 'postgres' (service name), NOT 'localhost'
          PGPASSWORD=secret psql -h postgres -U app -d appdb -c "SELECT 1 AS connected;"

      - name: Verify Redis connection via service hostname
        run: |
          # Note: use 'redis' (service name), NOT 'localhost'
          redis-cli -h redis ping

      - name: Run tests
        env:
          # Use service names as hostnames
          DATABASE_URL: postgresql://app:secret@postgres:5432/appdb
          REDIS_URL: redis://redis:6379
        run: npm ci && npm run test:integration

  # Python example with service containers
  python-with-postgres:
    name: Python Tests with PostgreSQL
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
          python-version: '3.12'
          cache: 'pip'

      - name: Install dependencies
        run: pip install -r requirements.txt psycopg2-binary pytest-asyncio

      - name: Run integration tests
        env:
          DATABASE_URL: postgresql://pytest:pytest@localhost:5432/pytest_db
        run: pytest tests/integration/ -v --tb=short
EOF

print_success "Created: $WORKFLOW_DIR/job-container.yml"

# -----------------------------------------------------------------------------
# 4. Demonstrate Docker concepts locally (if Docker is available)
# -----------------------------------------------------------------------------
print_step "Demonstrating Docker service concepts..."

if command -v docker &>/dev/null; then
  print_info "Docker is available. Demonstrating service container startup..."

  # Start a temporary postgres container
  print_info "Starting temporary PostgreSQL container (simulating a service container)..."
  docker run -d \
    --name gh-actions-demo-postgres \
    -e POSTGRES_PASSWORD=testpassword \
    -e POSTGRES_USER=testuser \
    -e POSTGRES_DB=testdb \
    -p 15432:5432 \
    --health-cmd "pg_isready -U testuser" \
    --health-interval 2s \
    --health-retries 10 \
    postgres:16-alpine 2>/dev/null || print_info "Container already running or failed - skipping"

  print_info "Waiting for health check..."
  for i in {1..20}; do
    STATUS=$(docker inspect --format='{{.State.Health.Status}}' gh-actions-demo-postgres 2>/dev/null || echo "unknown")
    if [ "$STATUS" = "healthy" ]; then
      print_success "PostgreSQL container is healthy!"
      break
    fi
    echo "  Attempt $i/20: status=$STATUS"
    sleep 2
  done || true

  print_info "Cleaning up demo container..."
  docker rm -f gh-actions-demo-postgres 2>/dev/null || true
  print_success "Container cleaned up."
else
  print_info "Docker not available - skipping live container demo."
  print_info "Health check pattern for reference:"
  echo ""
  echo "  docker run -d \\"
  echo "    --health-cmd 'pg_isready -U postgres' \\"
  echo "    --health-interval 10s \\"
  echo "    --health-timeout 5s \\"
  echo "    --health-retries 5 \\"
  echo "    postgres:16"
  echo ""
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
print_header "Demo Complete"
print_success "Generated workflow files in: $WORKFLOW_DIR"
echo ""
print_info "Files created:"
ls -1 "$WORKFLOW_DIR/"
echo ""
print_info "Key networking reminder:"
echo "  Direct runner job  → access services via localhost:<port>"
echo "  Container job      → access services via <service-name>:<port>"
