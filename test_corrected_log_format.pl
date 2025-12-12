#!/usr/bin/env perl

use strict;
use warnings;
use v5.32;
use FindBin;
use lib "$FindBin::Bin/lib";

print "🔧 Testing Corrected Sentry Log Format\n";
print "=" x 50 . "\n";
print "Following official spec: https://develop.sentry.dev/sdk/telemetry/logs/\n\n";

my $dsn = $ENV{SENTRY_TEST_DSN} || 'https://bc1b329862866abb9c8f70c5dac940aa@sentry.cgtmigration.com/9';
my $project_id = $1 if $dsn =~ m{/(\d+)$};

print "📡 DSN: $dsn\n";
print "📌 Project ID: $project_id\n\n";

use Sentry::SDK;
Sentry::SDK->init({
    dsn => $dsn,
    environment => "corrected-log-format",
    release => "log-format-fix-1.0",
    debug => 1,  # Enable to see envelope format
});

print "✅ SDK initialized\n\n";

my $test_id = "CORRECTED_" . time();

# Get logger instance
my $logger = Sentry::SDK->get_logger();

print "📊 Sending logs with corrected format...\n";
print "-" x 40 . "\n";

# Test 1: Simple log
print "1️⃣ Simple info log...\n";
$logger->info("Simple log test with corrected format $test_id", {
    test_id => $test_id,
    format => 'corrected_spec',
    test_number => 1,
});
print "   ✅ Sent\n\n";

# Test 2: Log with structured data
print "2️⃣ Log with rich structured data...\n";
$logger->error("Error log with structured data $test_id", {
    test_id => $test_id,
    format => 'corrected_spec',
    test_number => 2,
    error_details => {
        code => 'ERR_001',
        message => 'Test error',
        severity => 'high',
    },
    user_context => {
        user_id => 12345,
        username => 'testuser',
        email => 'test@example.com',
    },
    request_info => {
        method => 'POST',
        path => '/api/v1/test',
        duration_ms => 234,
        status_code => 500,
    },
});
print "   ✅ Sent\n\n";

# Test 3: Warning with metrics
print "3️⃣ Warning log with metrics...\n";
$logger->warn("Performance warning $test_id", {
    test_id => $test_id,
    format => 'corrected_spec',
    test_number => 3,
    metrics => {
        cpu_usage => 85.5,
        memory_mb => 1024,
        response_time_ms => 2500,
        threshold_exceeded => 1,
    },
});
print "   ✅ Sent\n\n";

# Test 4: Debug log with trace context
print "4️⃣ Debug log...\n";
$logger->debug("Debug information $test_id", {
    test_id => $test_id,
    format => 'corrected_spec',
    test_number => 4,
    debug_data => {
        step => 'initialization',
        variables => {
            var1 => 'value1',
            var2 => 'value2',
        },
    },
});
print "   ✅ Sent\n\n";

# Force flush all logs
print "🔄 Flushing logs to Sentry...\n";
my $flushed = $logger->buffer->flush();
print "✅ Flushed $flushed log records\n\n";

# Also send a comparison message using old method
print "📊 Sending comparison message (for reference)...\n";
Sentry::SDK->capture_message("Comparison message $test_id", 'info');
print "✅ Sent\n\n";

print "=" x 50 . "\n";
print "🎉 Tests Complete!\n\n";

print "📋 WHAT CHANGED:\n";
print "• Envelope type: 'log' (was 'event')\n";
print "• Format: Sentry Log Protocol (official spec)\n";
print "• Required fields: timestamp, level, body\n";
print "• Structured data: in 'attributes' field\n";
print "• SDK info: added to attributes\n\n";

print "🔍 CHECK IN SENTRY:\n";
print "1. Go to Project $project_id\n";
print "2. Environment: 'corrected-log-format'\n";
print "3. Look for test_id: $test_id\n";
print "4. Check if logs appear in:\n";
print "   • Logs section (if available)\n";
print "   • Issues section\n";
print "   • Discover/Events section\n\n";

print "💡 DEBUG INFO:\n";
print "• Check the debug output above for envelope format\n";
print "• Look for 'type': 'log' in the envelope\n";
print "• Verify attributes are properly structured\n\n";

print "📚 Reference:\n";
print "https://develop.sentry.dev/sdk/telemetry/logs/\n";