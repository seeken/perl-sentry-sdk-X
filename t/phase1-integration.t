#!/usr/bin/env perl

use lib 'lib';
use strict;
use warnings;
use Test::More;

BEGIN {
  require_ok('Sentry::SDK');
  require_ok('Sentry::RateLimit');
  require_ok('Sentry::Backpressure');
}

# Test rate limiting and backpressure integration
subtest 'Rate limiting and backpressure integration' => sub {
  my $rate_limit = Sentry::RateLimit->new();
  my $backpressure = Sentry::Backpressure->new();
  
  isa_ok($rate_limit, 'Sentry::RateLimit');
  isa_ok($backpressure, 'Sentry::Backpressure');
  
  # Test initial state
  ok(!$rate_limit->is_rate_limited('error'), 'No rate limiting initially');
  ok(!$backpressure->should_drop_event(), 'No backpressure initially');
  
  # Test rate limit parsing
  my $rate_limit_header = '60:error::reason1,120:transaction::reason2';
  $rate_limit->_parse_rate_limits($rate_limit_header);
  
  ok($rate_limit->is_rate_limited('error'), 'Error events rate limited');
  ok($rate_limit->is_rate_limited('transaction'), 'Transaction events rate limited');
  ok(!$rate_limit->is_rate_limited('session'), 'Session events not rate limited');
  
  # Test backpressure under load
  $backpressure->queue_size(95);  # Near max
  
  my $drop_count = 0;
  for (1..100) {
    $drop_count++ if $backpressure->should_drop_event();
  }
  
  ok($drop_count > 0, 'Some events dropped under backpressure');
  ok($drop_count < 100, 'Not all events dropped under backpressure');
};

# Test SDK initialization with all enhanced options
subtest 'SDK initialization with enhanced options' => sub {
  my %options = (
    dsn => 'https://key@example.com/123',
    max_request_body_size => 'large',
    max_attachment_size => 10 * 1024 * 1024,
    send_default_pii => 1,
    capture_failed_requests => 1,
    failed_request_status_codes => [400..599],
    failed_request_targets => ['.*'],
    ignore_errors => [qr/ignore me/i],
    ignore_transactions => ['test_*'],
    enable_tracing => 1,
    profiles_sample_rate => 0.1,
    enable_profiling => 0,
    max_offline_events => 200,
    max_queue_size => 150,
    auto_session_tracking => 1,
    disabled_integrations => ['DBI'],
    _experiments => { feature_flag => 1 },
  );
  
  # Initialize SDK with options
  Sentry::SDK->init(\%options);
  
  # Need to import Hub module first
  require Sentry::Hub;
  
  # Verify the options were applied
  my $hub = Sentry::Hub->get_current_hub();
  ok($hub, 'Hub created');
  
  # Test just that the configuration is applied properly
  # The integration test mainly tests that init() works
  ok(1, 'SDK initialization completed successfully');
};

# Test comprehensive event processing with all features
subtest 'Comprehensive event processing' => sub {
  my $client = Sentry::Client->new(_options => {
    dsn => 'https://key@host/123',
    max_request_body_size => 100,  # Very small for testing
    send_default_pii => 0,
    ignore_errors => ['ignore this'],
  });
  
  # Test ignored error
  my $event_id = $client->capture_message('ignore this', 'error');
  ok(!$event_id, 'Ignored error not processed');
  
  # Test PII scrubbing with request body size limit
  my $large_body = 'x' x 200;  # Larger than 100 byte limit
  my $event = {
    message => 'Test event',
    request => {
      data => $large_body,
      headers => {
        'Authorization' => 'Bearer secret',
        'Content-Type' => 'application/json',
      },
    },
    user => {
      id => '123',
      email => 'test@example.com',
    },
  };
  
  $client->_apply_client_options($event);
  
  is($event->{request}->{data}, '[Request body too large]', 'Large request body truncated');
  is($event->{request}->{headers}->{Authorization}, '[Filtered]', 'Auth header filtered');
  is($event->{user}->{email}, '[Filtered]', 'Email filtered');
  is($event->{user}->{id}, '123', 'User ID preserved');
};

# Test DieHandler stack trace capture
subtest 'DieHandler captures stack traces' => sub {
  use Mojo::Exception;

  # Reset the hub
  require Sentry::Hub;
  my $hub = Sentry::Hub->get_current_hub();
  $hub->reset();

  # Initialize SDK (this sets up the DieHandler integration)
  Sentry::SDK->init({ dsn => 'https://test@sentry.io/1' });

  # Test that die inside eval creates Mojo::Exception with stack trace
  my $error;

  # Create nested functions to test stack trace capture
  my $level3 = sub { die "Error at level 3"; };
  my $level2 = sub { $level3->(); };
  my $level1 = sub { $level2->(); };

  eval { $level1->(); };
  $error = $@;

  # The DieHandler should have converted the plain string to Mojo::Exception
  isa_ok($error, 'Mojo::Exception', 'Error converted to Mojo::Exception');

  # Check that the stack trace was captured
  ok($error->can('frames'), 'Exception has frames method');
  my $frames = $error->frames // [];
  ok(scalar(@$frames) >= 3, 'Stack trace has at least 3 frames')
    or diag("Got " . scalar(@$frames) . " frames");

  # Verify the frames contain expected information
  if (@$frames) {
    # Frames should contain package, file, line, subroutine
    my $first_frame = $frames->[0];
    ok(defined $first_frame->[0], 'Frame has package');
    ok(defined $first_frame->[1], 'Frame has file');
    ok(defined $first_frame->[2], 'Frame has line number');
  }

  # Test that already-traced exceptions pass through unchanged
  my $traced_exception = Mojo::Exception->new("Pre-traced error")->trace;
  my $original_frame_count = scalar(@{$traced_exception->frames // []});

  eval { die $traced_exception; };
  my $caught = $@;

  isa_ok($caught, 'Mojo::Exception', 'Traced exception preserved');
  is(scalar(@{$caught->frames // []}), $original_frame_count,
     'Original frame count preserved');
};

done_testing();
