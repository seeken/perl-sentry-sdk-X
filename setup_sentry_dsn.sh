#!/bin/bash

# Sentry Configuration for perl-sentry-sdk testing
export SENTRY_TEST_DSN="https://bc1b329862866abb9c8f70c5dac940aa@sentry.cgtmigration.com/9"

echo "Sentry DSN configured: $SENTRY_TEST_DSN"
echo "You can now run tests without specifying DSN manually:"
echo "  perl examples/phase6_demo.pl"
echo "  perl examples/sentry_live_test.pl"
echo ""
echo "To make this permanent, add this to your shell profile:"
echo "  echo 'export SENTRY_TEST_DSN=\"$SENTRY_TEST_DSN\"' >> ~/.zshrc"
echo "  source ~/.zshrc"