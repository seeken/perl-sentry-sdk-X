#!/bin/bash

# Sentry SDK Live Test Setup Script

echo "=== Perl Sentry SDK Live Test Setup ==="
echo

# Check if SENTRY_TEST_DSN is set
if [ -z "$SENTRY_TEST_DSN" ]; then
    echo "❌ Error: SENTRY_TEST_DSN environment variable is not set"
    echo
    echo "Please set your Sentry DSN like this:"
    echo "export SENTRY_TEST_DSN='https://YOUR_KEY@YOUR_ORG.ingest.sentry.io/YOUR_PROJECT_ID'"
    echo
    echo "Example:"
    echo "export SENTRY_TEST_DSN='https://abc123@o123456.ingest.sentry.io/789012'"
    echo
    echo "Then run this script again:"
    echo "./examples/run_live_test.sh"
    exit 1
fi

echo "✅ SENTRY_TEST_DSN is set"
echo "🎯 Target: $(echo $SENTRY_TEST_DSN | sed 's/https:\/\/[^@]*@/https:\/\/***@/')"
echo

# Check dependencies
echo "🔍 Checking dependencies..."

# Check if we're in the right directory
if [ ! -f "lib/Sentry/SDK.pm" ]; then
    echo "❌ Error: Please run this script from the perl-sentry-sdk root directory"
    exit 1
fi

# Check Perl modules
perl -c examples/sentry_live_test.pl > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "❌ Error: Script has syntax errors. Checking dependencies..."
    
    # Check individual modules
    perl -e "use DBI" 2>/dev/null || echo "⚠️  Warning: DBI module not found (database tests will be skipped)"
    perl -e "use LWP::UserAgent" 2>/dev/null || echo "⚠️  Warning: LWP::UserAgent not found (LWP tests will be skipped)"
    perl -e "use Mojo::UserAgent" 2>/dev/null || echo "⚠️  Warning: Mojo::UserAgent not found (Mojo tests will be skipped)"
    
    echo
    echo "To install missing dependencies:"
    echo "cpanm DBI DBD::SQLite LWP::UserAgent Mojolicious"
    echo
fi

echo "✅ Basic checks passed"
echo

# Run the live test
echo "🚀 Running live test..."
echo "This will send real telemetry data to your Sentry server"
echo

perl examples/sentry_live_test.pl

echo
echo "🎉 Live test completed!"
echo "Check your Sentry dashboard at: https://sentry.io/"
