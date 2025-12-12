#!/usr/bin/env perl

use strict;
use warnings;
use v5.32;
use FindBin;
use lib "$FindBin::Bin/lib";

print "🚀 Simplified Sentry Logging Test (Fixed Format)\n";
print "=" x 50 . "\n";

# DSN setup
my $dsn = $ENV{SENTRY_TEST_DSN} || 'https://bc1b329862866abb9c8f70c5dac940aa@sentry.cgtmigration.com/9';
print "📡 Using DSN: $dsn\n\n";

# Initialize Sentry
use Sentry::SDK;
Sentry::SDK->init({
    dsn => $dsn,
    environment => "test-logging-fixed",
    release => "logging-fix-1.0",
    debug => 1,
});

print "✅ Sentry SDK initialized\n\n";

# Get logger instance
my $logger = Sentry::SDK->get_logger();
print "✅ Logger instance obtained\n\n";

# Send test logs
print "📊 Sending test logs with corrected format...\n";
print "-" x 30 . "\n";

# Test different log levels
$logger->info("Info level log - Testing fixed format", {
    component => "test_script",
    action => "logging_test",
    version => "1.0",
    format_fix => "using_event_type"
});
print "  ✅ Info log sent\n";

$logger->warn("Warning level log - Something noteworthy", {
    component => "test_script",
    warning_type => "test_warning",
    threshold => 95,
    format_fix => "using_event_type"
});
print "  ✅ Warning log sent\n";

$logger->error("Error level log - Testing error tracking", {
    component => "test_script",
    error_code => "TEST_001",
    severity => "medium",
    format_fix => "using_event_type"
});
print "  ✅ Error log sent\n";

# Test structured data
$logger->info("Complex structured data test", {
    user => {
        id => 12345,
        email => 'test@example.com',
        role => 'admin'
    },
    request => {
        method => "POST",
        path => "/api/v1/test",
        duration_ms => 45
    },
    format_fix => "using_event_type"
});
print "  ✅ Structured data log sent\n";

# Force flush to ensure logs are sent immediately
print "\n🔄 Flushing logs to Sentry...\n";
my $flushed = $logger->buffer->flush();
print "✅ Flushed $flushed log records\n";

# Also send a regular error for comparison
print "\n📊 Sending regular error for comparison...\n";
eval {
    die "Test exception - This should appear in Issues";
};
if ($@) {
    Sentry::SDK->capture_exception($@);
    print "✅ Regular exception sent\n";
}

# Summary
print "\n" . "=" x 50 . "\n";
print "🎉 Test Complete!\n\n";
print "📋 What to check in Sentry:\n";
print "• The logs should now appear as Events in your Sentry project\n";
print "• Look for events with logger='perl-sentry-structured-logging'\n";
print "• The test exception should appear as a regular Issue\n";
print "• Extra context should be visible in the event details\n";
print "• All logs are now sent as 'event' type items (not 'log' type)\n\n";
print "⏱️  Check Sentry in 1-2 minutes for results\n";
print "🔗 Environment filter: 'test-logging-fixed'\n";
print "✅ Fix Applied: Changed from 'log' item type to 'event' item type\n";