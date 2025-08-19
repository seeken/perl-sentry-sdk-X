#!/usr/bin/env perl

use strict;
use warnings;
use feature 'say';

use lib '../lib';
use Sentry::SDK;
use Sentry::Integration::LwpUserAgent;
use LWP::UserAgent;
use Mojo::UserAgent;

# Initialize Sentry with minimal config
Sentry::SDK->init({
  dsn => $ENV{SENTRY_DSN} || 'https://bc1b329862866abb9c8f70c5dac940aa@sentry.cgtmigration.com/9',
  release => 'perl-sdk@1.3.9-phase5-simple',
  traces_sample_rate => 1.0,
  integrations => [
    Sentry::Integration::LwpUserAgent->new(),
  ],
});

say "🔗 Testing Simple Distributed Tracing";

# Start transaction
my $transaction = Sentry::SDK->start_transaction({
  name => 'simple_trace_test',
  op => 'test',
});

Sentry::Hub->get_current_hub()->get_scope()->set_span($transaction);

# Create child span for HTTP requests
my $http_span = $transaction->start_child({
  op => 'http.demo',
  description => 'HTTP requests with tracing'
});

Sentry::Hub->get_current_hub()->get_scope()->set_span($http_span);

# Make HTTP request - should include trace headers
my $ua = LWP::UserAgent->new();
say "📡 Making HTTP request with trace headers...";
my $response = $ua->get('https://httpbin.org/headers');

if ($response->is_success) {
  say "✅ Request successful: " . $response->code;
  # Parse JSON response to see headers that were sent
  if ($response->content =~ /"sentry-trace":\s*"([^"]+)"/) {
    say "🎉 sentry-trace header detected in request: $1";
  }
} else {
  say "❌ Request failed: " . $response->code;
}

$http_span->finish();
$transaction->finish();

say "✅ Test completed - check Sentry for trace data!";