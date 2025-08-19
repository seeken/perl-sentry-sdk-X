#!/usr/bin/env perl

use strict;
use warnings;
use lib 'lib';

use Sentry::SDK;
use Data::Dumper;

print "Testing Traditional Error Events from Phase 6\n";
print "=" x 50, "\n";

# Initialize SDK
my $dsn = $ENV{SENTRY_DSN} || $ENV{SENTRY_TEST_DSN};
if ($dsn) {
    print "Initializing Sentry SDK with DSN...\n";
    Sentry::SDK->init({
        dsn => $dsn,
        environment => 'test',
        release => 'error-test@1.0.0',
        enable_logs => 1,
    });
} else {
    die "No DSN provided - set SENTRY_TEST_DSN environment variable\n";
}

print "\n1. Direct SDK error (should show up in backend):\n";
Sentry::SDK->capture_message("Direct SDK error message", { 
    level => 'error',
    extra => { test => 'direct_sdk' },
});

print "\n2. Direct SDK exception (should show up in backend):\n";
eval { die "Direct SDK exception test" };
if ($@) {
    Sentry::SDK->capture_exception($@, {
        level => 'error',
        extra => { test => 'direct_sdk_exception' },
    });
}

print "\n3. Logger error-level message (should create dual events):\n";
my $logger = Sentry::SDK->get_logger();
$logger->error("Logger error message", {
    component => "test_component",
    error_type => "test_error"
});

print "\n4. Logger exception (should create dual events):\n";
eval { die "Logger exception test" };
if ($@) {
    $logger->log_exception($@, 'error', {
        operation => "test_operation",
        component => "test_exception_handler"
    });
}

print "\n5. Logger fatal message (should create dual events):\n";
$logger->fatal("Logger fatal message", {
    component => "critical_system",
    failure_type => "system_shutdown"
});

print "\nAll tests completed. Check Sentry dashboard for:\n";
print "  - 5 traditional error/exception events in Issues/Events section\n";
print "  - Structured log entries (if logs are enabled)\n";