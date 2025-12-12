#!/bin/bash

echo "🔍 Checking Sentry Logs Feature Support"
echo "========================================"
echo ""

# Check Sentry version
echo "1️⃣ Checking Sentry version..."
SENTRY_VERSION=$(docker exec sentry-web sentry --version 2>/dev/null || echo "Could not determine version")
echo "   Version: $SENTRY_VERSION"
echo ""

# Check if sentry.conf.py has logs configuration
echo "2️⃣ Checking sentry.conf.py for logs configuration..."
docker exec sentry-web grep -i "log" /etc/sentry/sentry.conf.py 2>/dev/null | grep -v "^#" | head -10 || echo "   Could not read sentry.conf.py"
echo ""

# Check if logs-related consumers are running
echo "3️⃣ Checking for logs-related consumers..."
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "(log|consumer)" || echo "   No log consumers found"
echo ""

# Check worker logs for log processing
echo "4️⃣ Checking worker logs for log processing..."
docker logs sentry-worker --since 5m 2>&1 | grep -i "log" | grep -v "Logged" | head -5 || echo "   No log-related activity"
echo ""

# Check if relay is processing logs
echo "5️⃣ Checking relay (if exists)..."
docker logs sentry-relay --since 5m 2>&1 | grep -E "(log|envelope)" | head -5 2>/dev/null || echo "   No relay container or no log activity"
echo ""

# Check feature flags
echo "6️⃣ Checking feature flags..."
docker exec sentry-web sentry exec -c "from sentry.features import *; print('Features module loaded')" 2>/dev/null || echo "   Could not check features"
echo ""

# Check for EAP (Event Analytics Platform) which handles logs
echo "7️⃣ Checking for EAP configuration (Event Analytics Platform)..."
docker exec sentry-web grep -i "eap" /etc/sentry/sentry.conf.py 2>/dev/null | grep -v "^#" || echo "   No EAP configuration found"
echo ""

echo "========================================"
echo "📋 Summary:"
echo ""
echo "If you see 'No log consumers found' or 'No EAP configuration',"
echo "your Sentry instance may not have the Logs feature enabled."
echo ""
echo "💡 To enable Logs in self-hosted Sentry:"
echo "1. Update sentry.conf.py to match the latest example"
echo "2. Run: docker-compose restart"
echo "3. Check release notes for your Sentry version"
echo ""
echo "📚 Reference:"
echo "https://github.com/getsentry/self-hosted/blob/master/sentry/sentry.conf.example.py"
echo ""
echo "⚠️  Alternative: If Logs feature is not available,"
echo "   logs will appear as Events in the Issues section instead."