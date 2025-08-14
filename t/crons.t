#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Test::MockModule;
use Time::HiRes;

# This test can run in two modes:
# 1. Mock mode (default): Uses mocked transport, no network calls
# 2. Real mode: Set SENTRY_TEST_DSN to test with real Sentry instance
#    Example: SENTRY_TEST_DSN="https://key@sentry.io/project" perl t/crons.t

my $use_real_dsn = $ENV{SENTRY_TEST_DSN};

BEGIN {
  # Only mock the transport if we don't have a real test DSN
  unless ($ENV{SENTRY_TEST_DSN}) {
    # Mock the transport to avoid network calls
    my $transport_mock = Test::MockModule->new('Sentry::Transport::Http');
    $transport_mock->mock('send', sub { 
      my ($self, $payload) = @_;
      # Store the payload for inspection
      $self->{_last_payload} = $payload;
      return { event_id => 'test-event-id' };
    });
    $transport_mock->mock('send_envelope', sub { 
      my ($self, $envelope) = @_;
      # Store the envelope for inspection
      $self->{_last_envelope} = $envelope;
      return { event_id => 'test-event-id' };
    });
  }
}

use_ok('Sentry::SDK');
use_ok('Sentry::Crons');
use_ok('Sentry::Crons::CheckIn');
use_ok('Sentry::Crons::Monitor');

# Initialize SDK
Sentry::SDK->init({
  dsn => $use_real_dsn || 'https://test_key@sentry.io/123456',
  debug => 1,
});

if ($use_real_dsn) {
  diag("Running tests with real Sentry DSN: $use_real_dsn");
} else {
  diag("Running tests with mocked transport (set SENTRY_TEST_DSN for real testing)");
}

# Test CheckIn class
subtest 'CheckIn basic functionality' => sub {
  my $checkin = Sentry::Crons::CheckIn->new(
    monitor_slug => 'test-monitor',
    status => 'in_progress',
    environment => 'test',
  );
  
  ok($checkin->check_in_id, 'CheckIn has auto-generated ID');
  is($checkin->monitor_slug, 'test-monitor', 'CheckIn has correct monitor slug');
  is($checkin->status, 'in_progress', 'CheckIn has correct status');
  is($checkin->environment, 'test', 'CheckIn has correct environment');
  
  # Test status updates
  $checkin->mark_ok(5000);
  is($checkin->status, 'ok', 'CheckIn marked as ok');
  is($checkin->duration, 5000, 'CheckIn has correct duration');
  
  $checkin->mark_error(3000);
  is($checkin->status, 'error', 'CheckIn marked as error');
  is($checkin->duration, 3000, 'CheckIn duration updated');
  
  # Test context
  $checkin->add_context('test_key', 'test_value');
  is($checkin->contexts->{test_key}, 'test_value', 'CheckIn context added');
  
  # Test envelope item
  my $item = $checkin->to_envelope_item();
  is($item->{monitor_slug}, 'test-monitor', 'Envelope item has monitor slug');
  is($item->{status}, 'error', 'Envelope item has status');
  is($item->{duration}, 3000, 'Envelope item has duration');
  is($item->{environment}, 'test', 'Envelope item has environment');
  is($item->{contexts}->{test_key}, 'test_value', 'Envelope item has context');
};

# Test Monitor class
subtest 'Monitor basic functionality' => sub {
  my $monitor = Sentry::Crons::Monitor->new(
    slug => 'test-monitor',
    name => 'Test Monitor',
    checkin_margin => 5,
    max_runtime => 30,
    timezone => 'UTC',
  );
  
  is($monitor->slug, 'test-monitor', 'Monitor has correct slug');
  is($monitor->name, 'Test Monitor', 'Monitor has correct name');
  
  # Test crontab schedule
  $monitor->set_crontab_schedule('0 2 * * *');
  is($monitor->schedule->{type}, 'crontab', 'Crontab schedule type set');
  is($monitor->schedule->{value}, '0 2 * * *', 'Crontab schedule value set');
  
  # Test interval schedule
  $monitor->set_interval_schedule(30, 'minute');
  is($monitor->schedule->{type}, 'interval', 'Interval schedule type set');
  is($monitor->schedule->{value}, 30, 'Interval schedule value set');
  is($monitor->schedule->{unit}, 'minute', 'Interval schedule unit set');
  
  # Test validation
  my @errors = $monitor->validate();
  is(scalar @errors, 0, 'Valid monitor has no errors');
  
  # Test invalid monitor
  my $invalid_monitor = Sentry::Crons::Monitor->new();
  @errors = $invalid_monitor->validate();
  ok(scalar @errors > 0, 'Invalid monitor has errors');
  
  # Test config generation
  my $config = $monitor->to_monitor_config();
  is($config->{slug}, 'test-monitor', 'Config has correct slug');
  is($config->{name}, 'Test Monitor', 'Config has correct name');
  is($config->{config}->{checkin_margin}, 5, 'Config has correct checkin margin');
};

# Test SDK cron methods
subtest 'SDK cron monitoring methods' => sub {
  # Mock the client to capture envelope
  my $hub = Sentry::Hub->get_current_hub();
  my $client = $hub->client;
  
  SKIP: {
    skip 'No client available for testing', 8 unless $client;
    
    # Test capture_check_in
    my $check_in_id = Sentry::SDK->capture_check_in({
      monitor_slug => 'test-job',
      status => 'in_progress',
      environment => 'test',
    });
    
    ok($check_in_id, 'capture_check_in returns ID');
    
    # Test update_check_in
    my $result = Sentry::SDK->update_check_in($check_in_id, 'ok', 5000);
    ok($result, 'update_check_in succeeds');
    
    # Test with_monitor
    my $executed = 0;
    my $return_value = Sentry::SDK->with_monitor('test-job', sub {
      $executed = 1;
      return 'test-result';
    });
    
    is($executed, 1, 'Code was executed in with_monitor');
    is($return_value, 'test-result', 'with_monitor returns code result');
    
    # Test with_monitor with exception
    my $exception_caught = 0;
    eval {
      Sentry::SDK->with_monitor('test-job', sub {
        die 'Test exception';
      });
    };
    
    $exception_caught = 1 if $@;
    like($@, qr/Test exception/, 'Exception was re-thrown') if $@;
    
    is($exception_caught, 1, 'Exception was caught and re-thrown');
    
    # Test upsert_monitor
    my $monitor_slug = Sentry::SDK->upsert_monitor({
      slug => 'test-monitor',
      name => 'Test Monitor',
      schedule => {
        type => 'crontab',
        value => '0 9 * * *',
      },
      checkin_margin => 10,
      max_runtime => 60,
      timezone => 'UTC',
    });
    
    is($monitor_slug, 'test-monitor', 'upsert_monitor returns slug');
    
    # If using a real DSN, we might want to add some delay to allow processing
    if ($use_real_dsn) {
      diag("Sent data to real Sentry instance - check your dashboard!");
      sleep(1);  # Give Sentry a moment to process
    }
  }
};

# Test Crons module directly
subtest 'Crons module functionality' => sub {
  # Test capture_check_in
  my $check_in_id = Sentry::Crons->capture_check_in({
    monitor_slug => 'direct-test',
    status => 'in_progress',
  });
  
  ok($check_in_id, 'Crons capture_check_in returns ID');
  
  # Check active check-ins
  my $active = Sentry::Crons->get_active_checkins();
  ok(exists $active->{$check_in_id}, 'Active check-in tracked');
  
  # Update check-in
  Sentry::Crons->update_check_in($check_in_id, 'ok', 2000);
  
  # Should be removed from active tracking
  $active = Sentry::Crons->get_active_checkins();
  ok(!exists $active->{$check_in_id}, 'Completed check-in removed from tracking');
  
  # Test with_monitor
  my $start_time = Time::HiRes::time();
  my $result = Sentry::Crons->with_monitor('timing-test', sub {
    Time::HiRes::sleep(0.1);  # 100ms
    return 'done';
  });
  my $elapsed = Time::HiRes::time() - $start_time;
  
  is($result, 'done', 'with_monitor returns result');
  ok($elapsed >= 0.1, 'Code actually executed');
  
  # Test upsert_monitor
  my $slug = Sentry::Crons->upsert_monitor({
    slug => 'direct-monitor',
    name => 'Direct Monitor',
    schedule => {
      type => 'interval',
      value => 30,
      unit => 'minute',
    },
  });
  
  is($slug, 'direct-monitor', 'upsert_monitor returns slug');
  
  # If using a real DSN, add a brief delay
  if ($use_real_dsn) {
    diag("Sent monitor configuration to real Sentry instance");
    sleep(1);
  }
};

# Test error handling
subtest 'Error handling' => sub {
  # Test capture_check_in without monitor_slug
  my $result = Sentry::Crons->capture_check_in({
    status => 'ok',
  });
  
  is($result, undef, 'capture_check_in fails without monitor_slug');
  
  # Test invalid monitor config
  $result = Sentry::Crons->upsert_monitor({
    name => 'Invalid Monitor',
    # Missing slug
  });
  
  is($result, undef, 'upsert_monitor fails with invalid config');
  
  # Test update_check_in with non-existent ID
  $result = Sentry::Crons->update_check_in('non-existent-id', 'ok');
  is($result, undef, 'update_check_in fails without original context');
};

done_testing;
