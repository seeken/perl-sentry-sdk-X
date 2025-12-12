#!/bin/bash

echo "🔍 Checking Sentry Log Processing"
echo "========================================"
echo ""

# Get the event ID from the last test
echo "1️⃣ Looking for recent log envelope processing..."
docker logs sentry-worker --since 10m 2>&1 | grep -i "log\|envelope" | tail -20

echo ""
echo "2️⃣ Checking for the specific event ID..."
# You'll need to replace this with the actual event ID from your test output
EVENT_ID="3882bea9027f465ea1db09a3a3243ba1"
docker logs sentry-worker --since 10m 2>&1 | grep -i "$EVENT_ID" || echo "Event ID not found in worker logs"

echo ""
echo "3️⃣ Checking relay for envelope processing..."
docker logs sentry-relay --since 10m 2>&1 | grep -E "(envelope|log)" | tail -20 2>/dev/null || echo "No relay container"

echo ""
echo "4️⃣ Checking for errors processing logs..."
docker logs sentry-worker --since 10m 2>&1 | grep -i "error" | grep -i "log" | tail -10

echo ""
echo "5️⃣ Checking Kafka/Celery queues..."
docker logs sentry-worker --since 5m 2>&1 | grep -i "received task" | tail -5

echo ""
echo "6️⃣ Checking if log item type is recognized..."
docker logs sentry-web --since 10m 2>&1 | grep -i "unknown.*type\|unsupported.*type" | tail -5

echo ""
echo "========================================"
echo "💡 Next steps:"
echo "1. If you see 'unknown type' or 'unsupported', the Sentry version may not support log items"
echo "2. If you see the event ID but no errors, logs may be silently dropped"
echo "3. Try checking Postgres directly to see if logs are stored"