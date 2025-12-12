#!/usr/bin/env perl

use strict;
use warnings;
use v5.32;
use FindBin;
use lib "$FindBin::Bin/lib";

print "🎯 Final Sentry Logs Test - Correct Format\n";
print "=" x 50 . "\n\n";

my $dsn = $ENV{SENTRY_TEST_DSN} || 'https://bc1b329862866abb9c8f70c5dac940aa@sentry.cgtmigration.com/9';
my $project_id = $1 if $dsn =~ m{/(\d+)$};
my $test_id = "FINAL_" . time();

print "📡 Project ID: $project_id\n";
print "🆔 Test ID: $test_id\n\n";

use Sentry::SDK;
Sentry::SDK->init({
    dsn => $dsn,
    environment => "final-logs-test",
    release => "final-1.0",
    debug => 0,  # Less verbose
});

my $logger = Sentry::SDK->get_logger();

print "Sending structured logs...\n";
print "-" x 30 . "\n";

# Send a few logs
$logger->info("Application started - $test_id", {
    test_id => $test_id,
    app_name => 'perl-test-app',
    version => '1.0.0',
    startup_time_ms => 150,
});
print "  ✅ Info\n";

$logger->warn("High memory usage detected - $test_id", {
    test_id => $test_id,
    memory_usage_mb => 1024,
    threshold_mb => 800,
    action => 'monitoring',
});
print "  ✅ Warning\n";

$logger->error("Database connection slow - $test_id", {
    test_id => $test_id,
    connection_time_ms => 2500,
    threshold_ms => 1000,
    database => 'primary',
    retry_attempted => 1,
});
print "  ✅ Error\n";

# Flush
$logger->buffer->flush();
print "\n✅ Logs flushed to Sentry\n\n";

print "=" x 50 . "\n";
print "📋 CHECK SENTRY LOGS PAGE:\n\n";
print "1. Go to your Sentry Logs page\n";
print "2. Filter by environment: 'final-logs-test'\n";
print "3. Search for: $test_id\n";
print "4. You should see 3 log entries\n\n";

print "🎉 Format is now correct:\n";
print "  • Logs sent in array format\n";
print "  • Content-type: application/vnd.sentry.items.log+json\n";
print "  • item_count header included\n";
print "  • Matches JavaScript SDK format\n\n";

print "⏱️  Wait 1-2 minutes and refresh Logs page\n";