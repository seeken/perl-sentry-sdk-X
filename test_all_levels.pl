#!/usr/bin/env perl

use strict;
use warnings;
use lib 'lib';

use Sentry::SDK;

print "Testing all log levels...\n";

# Initialize Sentry SDK
my $dsn = $ENV{SENTRY_DSN} || $ENV{SENTRY_TEST_DSN};
if ($dsn) {
    print "Using DSN: $dsn\n";
    Sentry::SDK->init({
        dsn => $dsn,
        environment => 'test',
    });
} else {
    print "No DSN - exiting\n";
    exit 1;
}

# Get logger and set minimum level to trace to capture everything
my $logger = Sentry::SDK->get_logger();
$logger->buffer->min_level('trace');
$logger->buffer->auto_flush(0);  # Disable auto-flush

print "Sending test events at all levels...\n";

# Send events at each level
$logger->trace("TRACE: This is a trace message", { test_type => 'level_test', level_num => 1 });
$logger->debug("DEBUG: This is a debug message", { test_type => 'level_test', level_num => 2 });
$logger->info("INFO: This is an info message", { test_type => 'level_test', level_num => 3 });
$logger->warn("WARN: This is a warning message", { test_type => 'level_test', level_num => 4 });
$logger->error("ERROR: This is an error message", { test_type => 'level_test', level_num => 5 });
$logger->fatal("FATAL: This is a fatal message", { test_type => 'level_test', level_num => 6 });

print "Buffer contains " . scalar(@{$logger->buffer->records}) . " records\n";

# Force flush all events
print "Flushing all events...\n";
my $sent_count = $logger->flush();
print "Sent $sent_count events\n";

print "Test completed - check Sentry for 6 events with test_type=level_test\n";
