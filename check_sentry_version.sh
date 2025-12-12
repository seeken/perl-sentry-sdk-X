#!/bin/bash

echo "🔍 Checking Self-Hosted Sentry Configuration"
echo "============================================"

# Function to check container logs
check_container() {
    local container=$1
    echo ""
    echo "📦 Checking $container..."
    if docker ps | grep -q "$container"; then
        echo "Recent errors/warnings:"
        docker logs "$container" --tail 100 2>&1 | grep -E "(ERROR|WARNING|error|warning|failed|Failed)" | tail -5

        echo ""
        echo "Event processing logs:"
        docker logs "$container" --tail 100 2>&1 | grep -E "(envelope|event|store)" | tail -5
    else
        echo "Container $container not found"
    fi
}

# Check Sentry version
echo ""
echo "📌 Sentry Version:"
docker exec sentry-web sentry --version 2>/dev/null || echo "Could not determine version"

# Check main containers
for container in sentry-web sentry-worker sentry-cron sentry-relay; do
    check_container "$container"
done

# Check Redis queue
echo ""
echo "📊 Redis Queue Status:"
docker exec sentry-redis redis-cli INFO | grep instantaneous_ops_per_sec 2>/dev/null || echo "Redis not accessible"

# Check recent event IDs
echo ""
echo "🔍 Recent Event Processing (last 5 minutes):"
docker logs sentry-worker --since 5m 2>&1 | grep -oE "event_id['\"]?:\s*['\"]?[a-f0-9]{32}" | tail -5

echo ""
echo "💡 To see real-time logs, run:"
echo "   docker logs -f sentry-worker"
echo ""
echo "💡 To check if events are stuck in queue:"
echo "   docker exec sentry-redis redis-cli LLEN default"
echo ""
echo "💡 To check Postgres directly:"
echo "   docker exec -it sentry-postgres psql -U postgres sentry -c 'SELECT created, message FROM sentry_message ORDER BY created DESC LIMIT 5;'"