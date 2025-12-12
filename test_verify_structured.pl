#!/usr/bin/env perl

use strict;
use warnings;
use v5.32;
use FindBin;
use lib "$FindBin::Bin/lib";

print "🔍 Verifying Structured Data in Sentry\n";
print "=" x 50 . "\n";

my $dsn = $ENV{SENTRY_TEST_DSN} || 'https://bc1b329862866abb9c8f70c5dac940aa@sentry.cgtmigration.com/9';
my $project_id = $1 if $dsn =~ m{/(\d+)$};

print "📡 DSN: $dsn\n";
print "📌 Project ID: $project_id\n\n";

use Sentry::SDK;
Sentry::SDK->init({
    dsn => $dsn,
    environment => "structured-verify",
    release => "structured-1.0",
    debug => 0,
});

# Test 1: Send a message with rich structured data
print "1️⃣ Sending message with structured data...\n";

my $test_id = "TEST_" . time();

# Configure scope with structured data
Sentry::SDK->configure_scope(sub {
    my $scope = shift;

    $scope->set_tag('test_id', $test_id);
    $scope->set_tag('component', 'logger');
    $scope->set_tag('version', '1.0');

    $scope->set_extra('test_purpose', 'verify_structured_data');
    $scope->set_extra('user_info', {
        id => 12345,
        email => 'test@example.com',
        role => 'admin',
    });
    $scope->set_extra('request_details', {
        method => 'POST',
        path => '/api/v1/test',
        duration_ms => 145,
        status_code => 200,
    });
    $scope->set_extra('metrics', {
        cpu_usage => 45.2,
        memory_mb => 512,
        active_connections => 23,
    });
    $scope->set_extra('nested_array', ['item1', 'item2', 'item3']);
    $scope->set_extra('timestamp', time());
    $scope->set_extra('readable_time', scalar(localtime()));

    $scope->set_user({
        id => 'user_12345',
        email => 'test@example.com',
    });

    $scope->set_context('custom_context', {
        type => 'test_context',
        data => 'additional_context_data',
    });
});

Sentry::SDK->capture_message(
    "Structured Log Test ID: $test_id",
    'info'
);
print "✅ Sent with test_id: $test_id\n\n";

# Clear scope for next test
Sentry::SDK->configure_scope(sub {
    my $scope = shift;
    $scope->clear();
});

# Test 2: Use logger to send structured log
print "2️⃣ Sending via Logger with structured data...\n";

my $logger = Sentry::SDK->get_logger();
$logger->error("Logger Structured Test ID: $test_id", {
    error_code => 'STRUCT_TEST',
    severity => 'medium',
    component => 'test_logger',
    diagnostic_info => {
        test_id => $test_id,
        format => 'structured',
        purpose => 'visibility_check',
    },
    business_data => {
        order_id => 'ORD-2024-001',
        amount => 299.99,
        currency => 'USD',
        items_count => 3,
    },
    system_info => {
        hostname => 'test-server',
        region => 'us-west',
        cluster => 'production',
    }
});

# Flush logs
$logger->buffer->flush();
print "✅ Sent via logger\n\n";

# Test 3: Send another message for comparison
print "3️⃣ Sending comparison message...\n";
Sentry::SDK->capture_message(
    "Simple comparison message without much data",
    'warning'
);
print "✅ Sent simple message\n\n";

print "=" x 50 . "\n";
print "📋 TO VERIFY IN SENTRY:\n\n";

print "1. Go to Project $project_id in Sentry\n";
print "2. Look for: 'Structured Log Test ID: $test_id'\n";
print "3. Click on that event\n";
print "4. Check these sections:\n";
print "   • 'Additional Data' or 'Extra' - Should show all nested data\n";
print "   • 'Tags' - Should show test_id, component, version\n";
print "   • 'User' - Should show user context\n";
print "   • 'Custom Context' - May appear in contexts\n\n";

print "5. Compare with the simple message to see the difference\n\n";

print "🔍 WHAT TO LOOK FOR:\n";
print "• user_info with nested id, email, role\n";
print "• request_details with method, path, duration_ms\n";
print "• metrics with cpu_usage, memory_mb\n";
print "• business_data with order information\n";
print "• All the structured fields should be browseable\n\n";

print "💡 IF DATA IS MISSING:\n";
print "• Try the 'Discover' or 'Events' section\n";
print "• Use search: test_id:$test_id\n";
print "• Check 'Raw' or 'JSON' view of the event\n";