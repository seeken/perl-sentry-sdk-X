#!/usr/bin/env perl

use lib 'lib';
use strict;
use warnings;
use Test::More;
use File::Temp;
use JSON::PP;

BEGIN {
  require_ok('Sentry::SDK');
  require_ok('Sentry::Client');
}

# Test enhanced client options configuration
subtest 'Enhanced client options configuration' => sub {
  my $client = Sentry::Client->new(_options => {
    dsn => 'https://key@host/123',
    max_request_body_size => 'small',
    send_default_pii => 0,
    capture_failed_requests => 1,
    failed_request_status_codes => [400..499, 500..599],
    failed_request_targets => ['.*api.*', qr/admin/],
    ignore_errors => ['Ignored error', qr/warning/i],
    ignore_transactions => ['test_transaction'],
    max_offline_events => 50,
  });
  
  isa_ok($client, 'Sentry::Client');
  is($client->get_max_request_body_size(), 10 * 1024, 'Small request body size');
  
  ok($client->should_capture_failed_request(500), 'Should capture 500 error');
  ok($client->should_capture_failed_request(404, 'https://api.example.com'), 'Should capture API 404');
  ok(!$client->should_capture_failed_request(200), 'Should not capture 200');
  ok(!$client->should_capture_failed_request(404, 'https://example.com'), 'Should not capture non-API 404');
  
  ok($client->should_ignore_error('Ignored error'), 'Should ignore exact match error');
  ok($client->should_ignore_error('This is a WARNING message'), 'Should ignore regex match error');
  ok(!$client->should_ignore_error('Important error'), 'Should not ignore other errors');
  
  ok($client->should_ignore_transaction('test_transaction'), 'Should ignore transaction');
  ok(!$client->should_ignore_transaction('important_transaction'), 'Should not ignore other transactions');
};

# Test request body size limits
subtest 'Request body size limits' => sub {
  my $client = Sentry::Client->new(_options => {
    dsn => 'https://key@host/123',
    max_request_body_size => 'never',
  });
  
  is($client->get_max_request_body_size(), 0, 'Never capture request body');
  
  $client = Sentry::Client->new(_options => {
    dsn => 'https://key@host/123',
    max_request_body_size => 'always',
  });
  
  is($client->get_max_request_body_size(), -1, 'Always capture request body');
  
  $client = Sentry::Client->new(_options => {
    dsn => 'https://key@host/123',
    max_request_body_size => 1024,
  });
  
  is($client->get_max_request_body_size(), 1024, 'Custom request body size');
};

# Test PII scrubbing
subtest 'PII scrubbing' => sub {
  my $client = Sentry::Client->new(_options => {
    dsn => 'https://key@host/123',
    send_default_pii => 0,
  });
  
  my $event = {
    request => {
      headers => {
        'Authorization' => 'Bearer token123',
        'Content-Type' => 'application/json',
        'X-API-Key' => 'secret123',
      },
      data => 'some data',
    },
    user => {
      id => '123',
      email => 'user@example.com',
      username => 'testuser',
    },
    extra => {
      password => 'secret123',
      normal_data => 'safe',
    },
  };
  
  $client->_scrub_pii($event);
  
  is($event->{request}->{headers}->{Authorization}, '[Filtered]', 'Authorization header filtered');
  is($event->{request}->{headers}->{'X-API-Key'}, '[Filtered]', 'API key header filtered');
  is($event->{request}->{headers}->{'Content-Type'}, 'application/json', 'Safe header preserved');
  
  is($event->{user}->{email}, '[Filtered]', 'User email filtered');
  is($event->{user}->{username}, '[Filtered]', 'Username filtered');
  is($event->{user}->{id}, '123', 'User ID preserved');
  
  is($event->{extra}->{password}, '[Filtered]', 'Password in extra filtered');
  is($event->{extra}->{normal_data}, 'safe', 'Normal data preserved');
};

# Test offline storage
subtest 'Offline event storage' => sub {
  my $temp_dir = File::Temp->newdir();
  my $client = Sentry::Client->new(_options => {
    dsn => 'https://key@host/123',
    offline_storage_path => "$temp_dir",
    max_offline_events => 2,
  });
  
  my $event = { message => 'Test offline event', event_id => 'test123' };
  
  $client->store_offline_event($event);
  
  my @files = glob("$temp_dir/sentry_event_*.json");
  is(scalar(@files), 1, 'One offline event stored');
  
  if (@files) {
    open my $fh, '<', $files[0];
    my $content = do { local $/; <$fh> };
    close $fh;
    
    my $stored_event = JSON::PP->new->decode($content);
    is($stored_event->{message}, 'Test offline event', 'Event stored correctly');
  }
};

# Test ignore patterns with callbacks
subtest 'Ignore patterns with callbacks' => sub {
  my $client = Sentry::Client->new(_options => {
    dsn => 'https://key@host/123',
    ignore_errors => [
      sub { $_[0] =~ /test/i },
      'exact match',
    ],
    ignore_transactions => [
      sub { $_[0] =~ /^test_/ },
    ],
  });
  
  ok($client->should_ignore_error('This is a TEST error'), 'Should ignore error via callback');
  ok($client->should_ignore_error('exact match'), 'Should ignore error via exact match');
  ok(!$client->should_ignore_error('Important error'), 'Should not ignore other errors');
  
  ok($client->should_ignore_transaction('test_something'), 'Should ignore transaction via callback');
  ok(!$client->should_ignore_transaction('important_transaction'), 'Should not ignore other transactions');
};

done_testing();
