#!/bin/bash

# Example script showing how to run crons tests with a real Sentry DSN

echo "=== Perl Sentry SDK Cron Monitoring Test Runner ==="
echo

if [ -z "$SENTRY_TEST_DSN" ]; then
    echo "No SENTRY_TEST_DSN set - running in mock mode"
    echo "Set SENTRY_TEST_DSN to test with a real Sentry instance:"
    echo "  export SENTRY_TEST_DSN='https://your_key@sentry.io/your_project'"
    echo "  $0"
    echo
    echo "Running mock tests now..."
    perl -Ilib t/crons.t
else
    echo "Using real Sentry DSN: $SENTRY_TEST_DSN"
    echo "Check your Sentry dashboard for cron monitoring data!"
    echo
    echo "Running real integration tests..."
    perl -Ilib t/crons.t
fi
