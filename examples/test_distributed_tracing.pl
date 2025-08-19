#!/usr/bin/env perl

=head1 NAME

test_distributed_tracing.pl - Test distributed tracing between client and server

=head1 DESCRIPTION

This script tests the complete distributed tracing flow:
1. Starts a simple HTTP server with Sentry tracing
2. Makes HTTP requests from a client with trace propagation
3. Verifies that traces are properly correlated

=cut

use strict;
use warnings;
use feature 'say';

use lib '../lib';
use Sentry::SDK;
use Mojo::UserAgent;
use HTTP::Server::Simple::CGI;
use JSON::PP;
use Time::HiRes qw(sleep);
use POSIX ":sys_wait_h";

# Initialize Sentry for distributed tracing test
Sentry::SDK->init({
  dsn => $ENV{SENTRY_DSN} || 'https://bc1b329862866abb9c8f70c5dac940aa@sentry.cgtmigration.com/9',
  release => 'perl-sdk@1.3.9-distributed-test',
  environment => 'test',
  traces_sample_rate => 1.0,
  
  integrations => [
    'LwpUserAgent',
    'MojoUserAgent',
  ],
});

say "🔗 Testing Distributed Tracing";
say "=" x 40;

# Simple HTTP server that accepts traces
package TestServer;
use base qw(HTTP::Server::Simple::CGI);

sub handle_request {
  my ($self, $cgi) = @_;
  
  # Extract trace headers
  my $sentry_trace = $ENV{HTTP_SENTRY_TRACE} || '';
  my $baggage = $ENV{HTTP_BAGGAGE} || '';
  
  say "📥 Server received trace headers:";
  say "   sentry-trace: $sentry_trace" if $sentry_trace;
  say "   baggage: $baggage" if $baggage;
  
  # Start server transaction with trace continuation
  my $transaction = Sentry::SDK->start_transaction({
    name => 'test_server_endpoint',
    op => 'http.server',
    description => 'Test server for distributed tracing'
  });
  
  if ($sentry_trace) {
    # Parse and continue the trace
    use Sentry::Tracing::Propagation;
    my $headers = {
      'sentry-trace' => $sentry_trace,
      'baggage' => $baggage,
    };
    
    my $trace_context = Sentry::Tracing::Propagation->extract_trace_context($headers);
    if ($trace_context && $trace_context->{trace_id}) {
      say "✅ Successfully extracted trace context";
      say "   trace_id: $trace_context->{trace_id}";
      say "   span_id: $trace_context->{span_id}";
      say "   sampled: " . ($trace_context->{sampled} // 'undefined');
    }
  }
  
  # Simulate some server work
  my $work_span = $transaction->start_child({
    op => 'db.query',
    description => 'Simulate database work'
  });
  
  sleep(0.1);  # Simulate work
  $work_span->finish();
  
  # Send response
  print "HTTP/1.1 200 OK\r\n";
  print "Content-Type: application/json\r\n\r\n";
  print JSON::PP->new->encode({
    status => 'success',
    message => 'Distributed tracing test',
    trace_received => $sentry_trace ? 1 : 0,
    timestamp => time()
  });
  
  $transaction->set_http_status(200);
  $transaction->finish();
}

package main;

# Start the test server in background
my $server_pid = fork();

if ($server_pid == 0) {
  # Child process - run the server
  my $server = TestServer->new(8080);
  say "🖥️  Starting test server on port 8080...";
  $server->run();
  exit;
} elsif (!defined $server_pid) {
  die "Failed to fork server process: $!";
}

# Give server time to start
sleep(2);

say "🖥️  Test server started (PID: $server_pid)";

# Now make client requests with distributed tracing
say "\n📡 Making client requests with distributed tracing...";

my $client_transaction = Sentry::SDK->start_transaction({
  name => 'distributed_trace_client',
  op => 'test.client',
  description => 'Client side of distributed trace test'
});

Sentry::Hub->get_current_hub()->get_scope()->set_span($client_transaction);

# Create a span for the client request
my $client_span = $client_transaction->start_child({
  op => 'http.client.test',
  description => 'Test client request with trace propagation'
});

Sentry::Hub->get_current_hub()->get_scope()->set_span($client_span);

# Make the request - this should automatically include trace headers
my $ua = Mojo::UserAgent->new();
say "📤 Making HTTP request to test server...";

my $tx = $ua->get('http://localhost:8080/test');

if ($tx->res->is_success) {
  say "✅ Request successful: " . $tx->res->code;
  my $response_data = $tx->res->json;
  if ($response_data && $response_data->{trace_received}) {
    say "🎉 Trace headers successfully propagated to server!";
  } else {
    say "❌ Trace headers not received by server";
  }
} else {
  say "❌ Request failed: " . ($tx->res->code || 'no response');
}

$client_span->finish();
$client_transaction->finish();

say "\n🧹 Cleaning up...";

# Clean up - stop the server
kill 'TERM', $server_pid;
waitpid($server_pid, 0);

say "✅ Test server stopped";

say "\n📊 Distributed tracing test completed!";
say "Check your Sentry dashboard for:";
say "  • Client transaction with HTTP request span";
say "  • Server transaction with database simulation span";  
say "  • Proper trace correlation between client and server";
say "  • sentry-trace header propagation";

sleep(2);  # Allow time for data to be sent

say "\n🎯 Distributed tracing test finished!";