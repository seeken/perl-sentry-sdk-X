#!/usr/bin/env perl

use strict;
use warnings;
use v5.32;
use FindBin;
use lib "$FindBin::Bin/lib";
use Mojo::JSON qw(encode_json);

print "🔬 Testing Proper Sentry Log Format\n";
print "=" x 50 . "\n";

my $dsn = $ENV{SENTRY_TEST_DSN} || 'https://bc1b329862866abb9c8f70c5dac940aa@sentry.cgtmigration.com/9';
print "📡 DSN: $dsn\n\n";

use Sentry::SDK;
Sentry::SDK->init({
    dsn => $dsn,
    environment => "format-test",
    release => "format-test-1.0",
    debug => 1,
});

my $hub = Sentry::SDK->get_current_hub();
my $client = $hub->client if $hub;

unless ($client) {
    die "Could not get Sentry client\n";
}

print "Testing different envelope formats...\n";
print "-" x 40 . "\n\n";

# Test 1: Standard event (known to work)
print "1️⃣ Standard exception event:\n";
eval { die "Test exception" };
if ($@) {
    Sentry::SDK->capture_exception($@);
    print "✅ Sent\n\n";
}

# Test 2: Event with logger field (current approach)
print "2️⃣ Event with logger field:\n";
{
    my $envelope = $client->_prepare_envelope();
    my $event = {
        timestamp => time(),
        level => 'info',
        logger => 'test.logger',
        platform => 'perl',
        message => 'Test log as event with logger',
        extra => {
            test_type => 'event_with_logger',
            format_version => 1,
        }
    };
    $envelope->add_item('event', $event);
    $client->_send_envelope($envelope);
    print "✅ Sent\n\n";
}

# Test 3: Using 'log' item type (might not be supported)
print "3️⃣ Log item type:\n";
{
    my $envelope = $client->_prepare_envelope();
    my $log_item = {
        timestamp => time(),
        level => 'info',
        logger => 'test.logger',
        message => 'Test using log item type',
        attributes => {
            test_type => 'log_item',
            format_version => 2,
        }
    };
    $envelope->add_item('log', $log_item);
    eval {
        $client->_send_envelope($envelope);
        print "✅ Sent\n\n";
    };
    if ($@) {
        print "❌ Failed: $@\n\n";
    }
}

# Test 4: Using breadcrumb format
print "4️⃣ As breadcrumb with event:\n";
{
    Sentry::SDK->add_breadcrumb({
        timestamp => time(),
        category => 'log',
        level => 'info',
        message => 'Test log as breadcrumb',
        data => {
            test_type => 'breadcrumb_log',
            format_version => 3,
        }
    });
    Sentry::SDK->capture_message("Event with breadcrumb log", 'info');
    print "✅ Sent\n\n";
}

# Test 5: Using logentry format (Python SDK style)
print "5️⃣ Event with logentry (Python SDK style):\n";
{
    my $envelope = $client->_prepare_envelope();
    my $event = {
        timestamp => time(),
        level => 'info',
        platform => 'perl',
        logentry => {
            formatted => 'Test log with logentry format',
            message => 'Test log with logentry format',
        },
        extra => {
            test_type => 'logentry_format',
            format_version => 4,
        }
    };
    $envelope->add_item('event', $event);
    $client->_send_envelope($envelope);
    print "✅ Sent\n\n";
}

# Test 6: Using OpenTelemetry-style format
print "6️⃣ OpenTelemetry-style format:\n";
{
    my $envelope = $client->_prepare_envelope();
    my $event = {
        timestamp => time(),
        level => 'info',
        platform => 'perl',
        logger => 'otel.logger',
        message => 'OpenTelemetry style log',
        contexts => {
            otel => {
                severity_text => 'INFO',
                severity_number => 9,
                body => 'OpenTelemetry style log',
                attributes => {
                    'test.type' => 'otel_format',
                    'format.version' => 5,
                }
            }
        },
        extra => {
            test_type => 'otel_format',
        }
    };
    $envelope->add_item('event', $event);
    $client->_send_envelope($envelope);
    print "✅ Sent\n\n";
}

# Test 7: Minimal format
print "7️⃣ Minimal event format:\n";
{
    my $envelope = $client->_prepare_envelope();
    my $event = {
        timestamp => time(),
        message => 'Minimal log event',
        level => 'info',
    };
    $envelope->add_item('event', $event);
    $client->_send_envelope($envelope);
    print "✅ Sent\n\n";
}

print "=" x 50 . "\n";
print "📋 Check your Sentry project for these events:\n";
print "• Filter by environment: 'format-test'\n";
print "• Look for events with different test_type values\n";
print "• The exception should definitely appear\n";
print "• Check which log formats show up correctly\n\n";

print "💡 In Sentry, check:\n";
print "1. Issues section\n";
print "2. Performance section\n";
print "3. Discover/Events section\n";
print "4. Any Logs section if available\n";