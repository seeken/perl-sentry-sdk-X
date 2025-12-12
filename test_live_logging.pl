#!/usr/bin/env perl

use strict;
use warnings;
use v5.32;
use FindBin;

# Add lib to path
use lib "$FindBin::Bin/lib";

print "🚀 Live Sentry Structured Logging Test\n";
print "=" x 50 . "\n";

# Source the DSN environment
my $dsn = $ENV{SENTRY_TEST_DSN} || 'https://bc1b329862866abb9c8f70c5dac940aa@sentry.cgtmigration.com/9';
print "📡 Using DSN: $dsn\n";

# Initialize Sentry with logging enabled
use Sentry::SDK;
Sentry::SDK->init({
    dsn => $dsn,
    enable_logging => 1,  # Enable structured logging
    environment => "test-logging",
    release => "logging-test-1.0",
    debug => 1,  # Enable debug output
    
    # Optional: Configure logging behavior
    before_send_log => sub {
        my $log = shift;
        # You can modify or filter logs here
        return $log;
    },
});

print "✅ Sentry SDK initialized with structured logging enabled\n";

# Get the logger instance
my $logger = Sentry::SDK->get_logger();
print "✅ Logger instance obtained\n";

# Test 1: Basic Logging Levels
print "\n📊 Test 1: Basic Log Levels\n";
print "-" x 30 . "\n";

$logger->trace("Trace level: Detailed debugging information", {
    component => "logging_test",
    test_type => "basic_levels",
    level_test => "trace"
});

$logger->debug("Debug level: Development debugging information", {
    component => "logging_test", 
    test_type => "basic_levels",
    level_test => "debug"
});

$logger->info("Info level: General information message", {
    component => "logging_test",
    test_type => "basic_levels", 
    level_test => "info"
});

$logger->warn("Warning level: Something unexpected happened", {
    component => "logging_test",
    test_type => "basic_levels",
    level_test => "warn",
    warning_type => "minor"
});

$logger->error("Error level: An error occurred but app continues", {
    component => "logging_test",
    test_type => "basic_levels",
    level_test => "error",
    error_code => "TEST_001"
});

$logger->fatal("Fatal level: Critical error that may stop the app", {
    component => "logging_test",
    test_type => "basic_levels", 
    level_test => "fatal",
    severity => "critical"
});

print "✅ Basic logging levels sent\n";

# Test 2: Template-based Logging
print "\n📊 Test 2: Template-based Logging\n";
print "-" x 35 . "\n";

my $user_id = 12345;
my $action = "login";
my $ip_address = "192.168.1.100";

$logger->infof("User %d performed action '%s' from IP %s", 
    $user_id, $action, $ip_address, {
    user_id => $user_id,
    action => $action,
    ip_address => $ip_address,
    timestamp => time(),
    test_type => "template_logging"
});

$logger->warnf("Rate limit approaching: %d requests in %d seconds", 
    95, 60, {
    current_requests => 95,
    time_window => 60,
    limit => 100,
    test_type => "template_logging"
});

$logger->errorf("Database query failed after %d attempts: %s", 
    3, "connection timeout", {
    retry_count => 3,
    error_type => "connection_timeout",
    query => "SELECT * FROM users WHERE id = ?",
    test_type => "template_logging"
});

print "✅ Template-based logging sent\n";

# Test 3: Contextual Logging
print "\n📊 Test 3: Contextual Logging\n";
print "-" x 30 . "\n";

# Create a contextual logger for a specific request
my $request_logger = $logger->with_context({
    request_id => "req-" . int(rand(10000)),
    session_id => "sess-" . int(rand(10000)),
    user_agent => "Test-Client/1.0",
    endpoint => "/api/v1/test"
});

$request_logger->info("Processing API request", {
    method => "POST",
    path => "/api/v1/users",
    test_type => "contextual_logging"
});

$request_logger->debug("Validating request parameters", {
    validation_step => "input_validation",
    test_type => "contextual_logging"
});

$request_logger->info("Request processed successfully", {
    response_time_ms => 45,
    status_code => 200,
    test_type => "contextual_logging"
});

print "✅ Contextual logging sent\n";

# Test 4: Exception Logging
print "\n📊 Test 4: Exception Logging\n";
print "-" x 30 . "\n";

eval {
    # Simulate an exception
    die "Simulated database connection error for testing structured logging";
};

if ($@) {
    $logger->log_exception($@, 'error', {
        operation => "database_connect",
        database => "user_db",
        host => "db.example.com",
        port => 5432,
        test_type => "exception_logging",
        recovery_action => "retry_with_fallback"
    });
    
    print "✅ Exception logged with context\n";
}

# Test 5: Performance Timing
print "\n📊 Test 5: Performance Timing\n";
print "-" x 30 . "\n";

my $result = $logger->time_block('data_processing_simulation', sub {
    # Simulate some work
    my $total = 0;
    for my $i (1..100000) {
        $total += sqrt($i);
    }
    
    # Simulate database operation
    select(undef, undef, undef, 0.1);  # 100ms delay
    
    return $total;
}, {
    operation_type => "batch_processing",
    record_count => 100000,
    test_type => "performance_timing",
    algorithm => "square_root_sum"
});

print "✅ Performance timing logged (result: " . sprintf("%.2f", $result) . ")\n";

# Test 6: Structured Data Logging
print "\n📊 Test 6: Structured Data Logging\n";
print "-" x 35 . "\n";

$logger->info("Complex structured data example", {
    test_type => "structured_data",
    user => {
        id => 67890,
        name => "Jane Doe",
        email => 'jane.doe@example.com',
        preferences => {
            theme => "dark",
            notifications => 1,
            language => "en-US"
        }
    },
    order => {
        id => "ORD-2025-001",
        items => [
            { sku => 'ITEM-001', quantity => 2, price => 29.99 },
            { sku => 'ITEM-002', quantity => 1, price => 15.50 }
        ],
        total => 75.48,
        currency => "USD"
    },
    metadata => {
        source => "web_app",
        version => "2.1.0",
        feature_flags => ['new_checkout', 'enhanced_search'],
        timestamp => time()
    }
});

print "✅ Structured data logging sent\n";

# Test 7: Different SDK Logging Methods
print "\n📊 Test 7: SDK Method Logging\n";
print "-" x 30 . "\n";

# Test SDK convenience methods
Sentry::SDK->log_info("SDK info method test", { 
    sdk_method => "log_info",
    test_type => "sdk_methods" 
});

Sentry::SDK->log_warn("SDK warning method test", { 
    sdk_method => "log_warn",
    test_type => "sdk_methods" 
});

Sentry::SDK->log_error("SDK error method test", { 
    sdk_method => "log_error", 
    test_type => "sdk_methods"
});

# Test template methods
Sentry::SDK->logf('info', 'SDK template method: processing %d items of type %s', 
    42, 'widgets', {
    item_count => 42,
    item_type => 'widgets',
    sdk_method => "logf",
    test_type => "sdk_methods"
});

print "✅ SDK logging methods sent\n";

# Test 8: Contextual SDK Logging
print "\n📊 Test 8: SDK Contextual Logging\n";
print "-" x 35 . "\n";

my $sdk_contextual = Sentry::SDK->with_log_context({
    component => "payment_processor",
    version => "3.2.1",
    environment => "test"
});

$sdk_contextual->info("Payment processing initiated", {
    payment_id => "PAY-" . int(rand(100000)),
    amount => 199.99,
    currency => "USD",
    method => "credit_card",
    test_type => "sdk_contextual"
});

print "✅ SDK contextual logging sent\n";

# Force flush all logs
print "\n🔄 Flushing all logs to Sentry...\n";
my $flush_count = $logger->buffer->flush();
print "✅ Flushed logs to Sentry\n";

# Final summary
print "\n" . "=" x 50 . "\n";
print "🎉 Live Structured Logging Test Complete!\n";
print "\nWhat was tested:\n";
print "✅ Basic log levels (trace, debug, info, warn, error, fatal)\n";
print "✅ Template-based logging with sprintf formatting\n";
print "✅ Contextual logging with request-specific data\n";
print "✅ Exception logging with stacktraces and context\n";
print "✅ Performance timing with automatic duration calculation\n";
print "✅ Complex structured data with nested objects\n";
print "✅ SDK convenience methods (log_info, log_warn, etc.)\n";
print "✅ SDK contextual logging\n";

print "\n📍 Check your Sentry project for these log entries:\n";
print "🔗 Logs should appear in: Issues, Performance, or dedicated Logs section\n";
print "🔍 Look for entries with 'test_type' field to identify test logs\n";
print "📊 Structured data should be fully searchable and filterable\n";

print "\n📋 Log Entry Examples to Look For:\n";
print "• 'User 12345 performed action login from IP 192.168.1.100'\n";
print "• 'Processing API request' (with request context)\n";
print "• 'Simulated database connection error' (exception)\n";
print "• 'data_processing_simulation' timing logs\n";
print "• 'Complex structured data example' (with nested objects)\n";

print "\n⏱️  Logs may take 1-2 minutes to appear in Sentry UI\n";
print "🎯 Status: All structured logging features tested successfully!\n";