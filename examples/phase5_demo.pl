#!/usr/bin/env perl

=head1 NAME

Phase 5 Demo - Enhanced HTTP Client Integration & Distributed Tracing

=head1 DESCRIPTION

Demonstrates comprehensive HTTP client integration with distributed tracing support:
- Trace propagation across HTTP requests
- Enhanced telemetry for LWP and Mojo UserAgents
- Failed request capture
- Performance monitoring
- Distributed tracing between services

=cut

use strict;
use warnings;
use feature 'say';

use lib '../lib';

use Sentry::SDK;
use Sentry::Integration::CaptureWarn;
use Sentry::Integration::DieHandler;
use Sentry::Integration::LwpUserAgent;
use Sentry::Integration::MojoUserAgent;
use LWP::UserAgent;
use Mojo::UserAgent;
use JSON::PP;
use Data::Dumper;
use Time::HiRes qw(sleep);

# Initialize Sentry with enhanced HTTP client options
Sentry::SDK->init({
  dsn => $ENV{SENTRY_DSN} || 'https://bc1b329862866abb9c8f70c5dac940aa@sentry.cgtmigration.com/9',
  release => 'perl-sdk@1.3.9-phase5',
  environment => 'development',
  traces_sample_rate => 1.0,
  
  # Enhanced HTTP client options
  capture_failed_requests => 1,
  capture_4xx_errors => 0,  # Only capture 5xx by default
  
  # Disable default integrations to avoid duplicates
  disabled_integrations => ['LwpUserAgent', 'MojoUserAgent', 'DieHandler'],
  
  integrations => [
    Sentry::Integration::CaptureWarn->new(),
    Sentry::Integration::DieHandler->new(),
    Sentry::Integration::LwpUserAgent->new(),
    Sentry::Integration::MojoUserAgent->new(),
  ],
  
  before_send => sub {
    my ($event, $hint) = @_;
    say "📤 Sending event: " . ($event->{message}{formatted} // $event->{transaction} // 'unknown');
    return $event;
  },
});

say "🚀 Phase 5 Demo - Enhanced HTTP Client Integration & Distributed Tracing";
say "=" x 70;

# Start a parent transaction to demonstrate distributed tracing
my $transaction = Sentry::SDK->start_transaction({
  name => 'phase5_demo_workflow',
  op => 'task',
  description => 'Demonstrate enhanced HTTP client integration',
});

Sentry::Hub->get_current_hub()->get_scope()->set_span($transaction);

# Demo 1: LWP::UserAgent with distributed tracing
say "\n📡 Demo 1: LWP::UserAgent with Distributed Tracing";
say "-" x 50;

my $lwp = LWP::UserAgent->new(
  timeout => 10,
  agent => 'Perl-Sentry-SDK/1.3.9 Phase5 Demo',
);

# Make requests that will carry trace context
my $span1 = $transaction->start_child({
  op => 'http.client.demo',
  description => 'LWP demo requests',
});

Sentry::Hub->get_current_hub()->get_scope()->set_span($span1);

# Successful request
say "Making successful HTTP request...";
my $response1 = $lwp->get('https://httpbin.org/status/200');
say "✅ Status: " . $response1->code . " - " . $response1->message;

# Request with custom headers
say "Making request with custom headers...";
my $request = HTTP::Request->new(GET => 'https://httpbin.org/headers');
$request->header('X-Demo-Header' => 'Phase5-Test');
my $response2 = $lwp->request($request);
say "✅ Headers request status: " . $response2->code;

# Failed request (this should be captured)
say "Making failed request (500 error)...";
my $response3 = $lwp->get('https://httpbin.org/status/500');
say "❌ Failed request status: " . $response3->code . " (should be captured)";

$span1->finish();

# Demo 2: Mojo::UserAgent with enhanced tracing
say "\n🌐 Demo 2: Mojo::UserAgent with Enhanced Tracing";
say "-" x 50;

my $mojo = Mojo::UserAgent->new();

my $span2 = $transaction->start_child({
  op => 'http.client.mojo',
  description => 'Mojo UserAgent demo',
});

Sentry::Hub->get_current_hub()->get_scope()->set_span($span2);

# JSON POST request
say "Making JSON POST request...";
my $post_data = { message => 'Phase 5 Demo', timestamp => time() };
my $tx1 = $mojo->post('https://httpbin.org/post' => json => $post_data);
say "✅ POST Status: " . $tx1->res->code;

# Request with query parameters
say "Making GET request with parameters...";
my $tx2 = $mojo->get('https://httpbin.org/get?demo=phase5&version=1.3.9');
say "✅ GET with params status: " . $tx2->res->code;

# Another failed request
say "Making failed request (404)...";
my $tx3 = $mojo->get('https://httpbin.org/status/404');
say "⚠️  Not Found request status: " . $tx3->res->code . " (4xx not captured by default)";

$span2->finish();

# Demo 3: Concurrent requests to show trace correlation
say "\n🔀 Demo 3: Concurrent Requests with Trace Correlation";
say "-" x 50;

my $span3 = $transaction->start_child({
  op => 'concurrent.demo',
  description => 'Multiple concurrent HTTP requests',
});

Sentry::Hub->get_current_hub()->get_scope()->set_span($span3);

# Create child spans for concurrent operations
my @child_spans;
for my $i (1..3) {
  my $child_span = $span3->start_child({
    op => 'http.client.concurrent',
    description => "Concurrent request $i",
    data => { request_number => $i }
  });
  
  push @child_spans, $child_span;
  
  # Set the span as active for this request
  Sentry::Hub->get_current_hub()->get_scope()->set_span($child_span);
  
  say "Starting concurrent request $i...";
  my $response = $lwp->get("https://httpbin.org/delay/1");
  say "✅ Concurrent request $i completed: " . $response->code;
  
  $child_span->finish();
}

$span3->finish();

# Demo 4: Error handling and capture
say "\n🚨 Demo 4: Enhanced Error Handling";
say "-" x 50;

my $span4 = $transaction->start_child({
  op => 'error.demo',
  description => 'Error handling demonstration',
});

Sentry::Hub->get_current_hub()->get_scope()->set_span($span4);

# This should trigger error capture
say "Making request to non-existent domain...";
eval {
  my $response = $lwp->get('https://definitely-does-not-exist.invalid');
  say "Response: " . ($response ? $response->code : 'no response');
};
if ($@) {
  say "❌ Request failed as expected: $@";
  Sentry::SDK->capture_exception($@);
}

# Server error that should be captured
say "Making request that returns 503...";
my $response4 = $lwp->get('https://httpbin.org/status/503');
say "❌ Server error: " . $response4->code . " (should be captured)";

$span4->finish();

# Demo 5: Custom baggage and trace data
say "\n🎒 Demo 5: Custom Trace Data and Baggage";
say "-" x 50;

my $span5 = $transaction->start_child({
  op => 'custom.baggage.demo',
  description => 'Custom baggage and trace data',
  data => {
    custom_field => 'phase5_demo',
    demo_version => '1.3.9',
    user_type => 'developer',
  }
});

Sentry::Hub->get_current_hub()->get_scope()->set_span($span5);

# Add custom tags
$span5->set_tag('demo.phase', '5');
$span5->set_tag('client.type', 'enhanced');

say "Making request with custom trace data...";
my $response5 = $lwp->get('https://httpbin.org/user-agent');
say "✅ Custom data request: " . $response5->code;

$span5->finish();

# Finish the main transaction
$transaction->finish();

say "\n✨ Demo completed! Check your Sentry dashboard for:";
say "   • Distributed traces across HTTP requests";
say "   • Enhanced telemetry data (OpenTelemetry format)";  
say "   • Failed request capture (5xx errors)";
say "   • Performance monitoring with durations";
say "   • Trace correlation between operations";
say "   • Custom baggage and trace data";

say "\n🔍 All HTTP requests include sentry-trace headers for distributed tracing";
say "📊 Performance data and error telemetry sent to Sentry";

# Keep process alive briefly to ensure all async operations complete
sleep(2);

say "\n🎯 Phase 5 Enhanced HTTP Client Integration demo completed!";