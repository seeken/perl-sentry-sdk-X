#!/usr/bin/env perl

use strict;
use warnings;
use lib 'lib';

use Sentry::SDK;
use Time::HiRes qw(sleep);

print "Phase 6: Structured Logging Support Demo\n";
print "=" x 50, "\n\n";

# Initialize Sentry SDK
my $dsn = $ENV{SENTRY_DSN} || $ENV{SENTRY_TEST_DSN};
if ($dsn) {
    print "Initializing Sentry SDK with DSN...\n";
    Sentry::SDK->init({
        dsn => $dsn,
        environment => 'demo',
        release => 'phase6-demo@1.0.0',
        enable_logs => 1,  # Enable structured logging support
    });
} else {
    print "No DSN provided - running in mock mode\n";
    Sentry::SDK->init({
        enable_logs => 1,  # Enable structured logging support even in mock mode
    });
}

print "\n1. Basic Structured Logging\n";
print "-" x 30, "\n";

# Get logger instance
my $logger = Sentry::SDK->get_logger();

# Set minimum level to debug to capture more events for demo
$logger->buffer->min_level('debug') if $dsn;

# Basic logging with context
$logger->info("Application started", {
    version => "1.0.0",
    environment => "demo",
    user_id => 12345,
});

$logger->debug("Debug information", {
    memory_usage => "64MB",
    cpu_usage => "15%",
});

$logger->warn("Performance warning", {
    response_time_ms => 1500,
    threshold_ms => 1000,
});

print "\n2. Template-based Logging\n";
print "-" x 30, "\n";

# Template-based logging
$logger->infof("Processing %d items for user %s", 150, "alice", {
    batch_id => "batch_001",
    priority => "high",
});

$logger->errorf("Database query failed after %d attempts", 3, {
    table => "users",
    error_code => "CONN_TIMEOUT",
});

print "\n3. Contextual Logging\n";
print "-" x 30, "\n";

# Create contextual logger
my $request_logger = $logger->with_context({
    request_id => "req_abc123",
    user_agent => "Demo/1.0",
    ip_address => "192.168.1.100",
});

$request_logger->info("Request received");
$request_logger->debug("Validating input");
$request_logger->info("Request processed successfully");

print "\n4. Transaction-aware Logging\n";
print "-" x 30, "\n";

# Transaction-aware logging
my $tx_logger = $logger->with_transaction("payment_processing", {
    payment_method => "credit_card",
    amount => 99.99,
    currency => "USD",
});

$tx_logger->info("Payment processing started");
$tx_logger->debug("Validating payment details");
$tx_logger->info("Payment processed successfully");

print "\n5. Exception Logging\n";
print "-" x 30, "\n";

# Exception logging
eval {
    die "Simulated database connection error";
};

if ($@) {
    $logger->log_exception($@, 'error', {
        operation => "database_connect",
        host => "db.example.com",
        port => 5432,
        retry_count => 3,
    });
}

print "\n6. Performance Timing\n";
print "-" x 30, "\n";

# Performance timing
my $result = $logger->time_block("slow_operation", sub {
    print "  Performing slow operation...\n";
    sleep(0.5);  # Simulate slow work
    return "operation completed";
}, {
    operation_type => "data_processing",
    expected_duration_ms => 500,
});

print "  Result: $result\n";

print "\n7. SDK Direct Logging Methods\n";
print "-" x 30, "\n";

# SDK convenience methods
Sentry::SDK->log_info("SDK info message", {
    component => "auth_service",
    status => "healthy",
});

Sentry::SDK->log_error("SDK error message", {
    component => "payment_service", 
    error_type => "validation_failed",
});

print "\n8. Log Level Demonstration\n";
print "-" x 30, "\n";

# All log levels
$logger->trace("Trace level - detailed debugging", { debug_level => "verbose" });
$logger->debug("Debug level - development info", { debug_info => "detailed" });
$logger->info("Info level - general information", { info_type => "status" });
$logger->warn("Warn level - potential issues", { warning_type => "performance" });
$logger->error("Error level - error conditions", { error_severity => "medium" });
$logger->fatal("Fatal level - critical failures", { error_severity => "critical" });

print "\n9. Buffer Management\n";
print "-" x 30, "\n";

# Get buffer statistics
my $stats = $logger->stats();
print "Logger statistics:\n";
print "  Enabled: " . ($stats->{enabled} ? "Yes" : "No") . "\n";
print "  Buffer size: " . $stats->{buffer}{record_count} . "\n";
print "  Min level: " . $stats->{buffer}{min_level} . "\n";

# Manual flush
print "Flushing logs to Sentry...\n";
my $sent_count = Sentry::SDK->flush_logs();
print "Sent $sent_count log records\n";

print "\n10. Advanced Features\n";
print "-" x 30, "\n";

# Configure logger
$logger->configure({
    buffer => {
        max_size => 25,
        flush_interval => 15,
        min_level => 'debug',
    }
});

# Multiple loggers with different contexts
my $api_logger = $logger->with_context({
    component => "api_server",
    version => "2.1.0",
});

my $db_logger = $logger->with_context({
    component => "database",
    connection_pool => "primary",
});

$api_logger->info("API request processed", {
    endpoint => "/users/123",
    method => "GET",
    status_code => 200,
});

$db_logger->debug("Query executed", {
    query => "SELECT * FROM users WHERE id = ?",
    execution_time_ms => 45,
    rows_returned => 1,
});

# Force flush all buffered logs before exit
if ($dsn) {
    print "\nFlushing all logs to Sentry...\n";
    my $sent_count = $logger->flush();
    print "Sent $sent_count log entries\n";
}

print "\nDemo completed!\n\n";

if ($dsn) {
    print "Check your Sentry dashboard to see the structured log entries.\n";
    print "Look for:\n";
    print "  - Rich context information\n";
    print "  - Performance timing data\n";
    print "  - Exception details with stacktraces\n";
    print "  - Transaction correlation\n";
    print "  - OpenTelemetry-compliant severity levels\n";
} else {
    print "Run with SENTRY_DSN environment variable to send logs to Sentry.\n";
}

print "\nStructured logging provides:\n";
print "  ✓ Rich context and metadata\n";
print "  ✓ Template-based formatting\n";
print "  ✓ Automatic performance timing\n";
print "  ✓ Exception handling with stacktraces\n";
print "  ✓ Transaction and trace correlation\n";
print "  ✓ Buffered transmission for efficiency\n";
print "  ✓ OpenTelemetry compliance\n";
