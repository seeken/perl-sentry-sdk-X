#!/usr/bin/env perl

use strict;
use warnings;
use v5.32;
use FindBin;
use lib "$FindBin::Bin/lib";

print "🔄 Testing Logs as Events (Fallback Method)\n";
print "=" x 50 . "\n";
print "This sends logs as regular events which work on ALL Sentry versions\n\n";

my $dsn = $ENV{SENTRY_TEST_DSN} || 'https://bc1b329862866abb9c8f70c5dac940aa@sentry.cgtmigration.com/9';
my $project_id = $1 if $dsn =~ m{/(\d+)$};
my $test_id = "EVENTS_" . time();

print "📡 Project ID: $project_id\n";
print "🆔 Test ID: $test_id\n\n";

use Sentry::SDK;
Sentry::SDK->init({
    dsn => $dsn,
    environment => "logs-as-events-test",
    release => "events-fallback-1.0",
    debug => 0,
});

print "Sending logs as events...\n";
print "-" x 30 . "\n";

# Method 1: Use capture_message (appears in Issues)
Sentry::SDK->with_scope(sub {
    my $scope = shift;
    $scope->set_tag('log_level', 'info');
    $scope->set_tag('test_id', $test_id);
    $scope->set_extra('structured_data', {
        app_name => 'perl-test-app',
        version => '1.0.0',
        startup_time_ms => 150,
    });

    Sentry::SDK->capture_message("INFO: Application started - $test_id", 'info');
});
print "  ✅ Info log (as message)\n";

Sentry::SDK->with_scope(sub {
    my $scope = shift;
    $scope->set_tag('log_level', 'warning');
    $scope->set_tag('test_id', $test_id);
    $scope->set_extra('structured_data', {
        memory_usage_mb => 1024,
        threshold_mb => 800,
        action => 'monitoring',
    });

    Sentry::SDK->capture_message("WARNING: High memory usage - $test_id", 'warning');
});
print "  ✅ Warning log (as message)\n";

Sentry::SDK->with_scope(sub {
    my $scope = shift;
    $scope->set_tag('log_level', 'error');
    $scope->set_tag('test_id', $test_id);
    $scope->set_extra('structured_data', {
        connection_time_ms => 2500,
        threshold_ms => 1000,
        database => 'primary',
        retry_attempted => 1,
    });

    Sentry::SDK->capture_message("ERROR: Database connection slow - $test_id", 'error');
});
print "  ✅ Error log (as message)\n\n";

print "=" x 50 . "\n";
print "✅ Logs sent as events!\n\n";

print "📋 CHECK SENTRY:\n";
print "1. Go to Issues section (NOT Logs)\n";
print "2. Filter by environment: 'logs-as-events-test'\n";
print "3. Search for: $test_id\n";
print "4. You should see 3 message events\n";
print "5. Click on each to see structured data in 'Additional Data'\n\n";

print "💡 This method works on ALL Sentry versions!\n";
print "   Logs appear as Messages in the Issues section.\n";