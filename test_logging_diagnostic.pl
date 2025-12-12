#!/usr/bin/env perl

use strict;
use warnings;
use v5.32;
use FindBin;

# Add lib to path
use lib "$FindBin::Bin/lib";

print "🔍 Sentry Logging Diagnostic Test\n";
print "=" x 50 . "\n";

# Source the DSN environment
my $dsn = $ENV{SENTRY_TEST_DSN} || 'https://bc1b329862866abb9c8f70c5dac940aa@sentry.cgtmigration.com/9';
print "📡 Using DSN: $dsn\n";

# Test 1: Check if we need to enable logging in init
print "\n🔧 Test 1: SDK Initialization with explicit logging enabled\n";
print "-" x 50 . "\n";

use Sentry::SDK;
Sentry::SDK->init({
    dsn => $dsn,
    environment => "logging-diagnostic",
    release => "diagnostic-1.0",
    debug => 1,
    
    # Try different ways to enable logging
    enable_logging => 1,
    enable_logs => 1,  # Alternative name
    
    # Configure logging behavior
    before_send_log => sub {
        my $log = shift;
        print "🔍 before_send_log hook called with: " . (ref($log) || 'scalar') . "\n";
        return $log;
    },
});

print "✅ SDK initialized with logging flags\n";

# Test 2: Send a simple message to error endpoint (should work)
print "\n🔧 Test 2: Standard Error Message (for comparison)\n";
print "-" x 50 . "\n";

eval {
    die "Test error for comparison - this should appear in Sentry";
};
if ($@) {
    Sentry::SDK->capture_exception($@);
    print "✅ Error sent via standard method\n";
}

# Test 3: Try manual log record creation
print "\n🔧 Test 3: Manual Log Record Creation\n";
print "-" x 50 . "\n";

require Sentry::Logger::LogRecord;
my $record = Sentry::Logger::LogRecord->new(
    level => 'error',
    message => 'Manual diagnostic log message',
    context => {
        test_type => "manual_diagnostic",
        timestamp => time(),
        method => "direct_record_creation",
    },
);

print "✅ Log record created\n";
print "  Level: " . $record->level . "\n";
print "  Message: " . $record->message . "\n";

# Check what the record looks like as envelope item
my $envelope_item = $record->to_envelope_item();
print "✅ Envelope item created\n";
print "  Type: " . (ref($envelope_item) || 'scalar') . "\n";

use Data::Dumper;
print "📋 Envelope item structure:\n";
print Dumper($envelope_item);

# Test 4: Try logging via different methods
print "\n🔧 Test 4: Different Logging Methods\n";
print "-" x 40 . "\n";

my $logger = Sentry::SDK->get_logger();
print "✅ Logger obtained: " . (ref($logger) || 'no logger') . "\n";

if ($logger) {
    print "  Logger enabled: " . ($logger->enabled ? "YES" : "NO") . "\n";
    
    # Try direct buffer manipulation
    print "\n📊 Testing direct buffer access:\n";
    my $buffer = $logger->buffer;
    print "  Buffer class: " . ref($buffer) . "\n";
    print "  Buffer records before: " . @{$buffer->records || []} . "\n";
    
    # Add record directly to buffer
    $buffer->add($record);
    print "  Buffer records after add: " . @{$buffer->records || []} . "\n";
    
    # Try manual flush
    print "\n🔄 Manual buffer flush:\n";
    my $flush_result = $buffer->flush();
    print "  Flush result: $flush_result\n";
    
    # Test simple logging
    print "\n📝 Simple logging test:\n";
    $logger->error("Direct logger error test", {
        diagnostic => 1,
        test_method => "logger_direct",
        severity => "high"
    });
    print "  ✅ Direct logger call completed\n";
    
    # Check buffer again
    print "  Buffer records after logging: " . @{$buffer->records || []} . "\n";
    
    # Force another flush
    my $flush_result2 = $buffer->flush();
    print "  Second flush result: $flush_result2\n";
}

# Test 5: Try sending via capture_message (alternative approach)
print "\n🔧 Test 5: Alternative - Capture Message\n";
print "-" x 40 . "\n";

Sentry::SDK->capture_message("Alternative log message via capture_message", 'error', {
    test_type => "capture_message_alternative",
    diagnostic => 1,
    method => "capture_message"
});
print "✅ Message sent via capture_message\n";

# Test 6: Check if logs are being sent as events instead
print "\n🔧 Test 6: Check Client Methods\n";
print "-" x 30 . "\n";

my $hub = Sentry::SDK->get_current_hub();
if ($hub) {
    my $client = $hub->client;
    if ($client) {
        print "✅ Client available: " . ref($client) . "\n";
        
        # Check what methods the client has
        my @methods = grep { $client->can($_) } qw(
            send_envelope _send_envelope _prepare_envelope
            capture_message capture_event capture_exception
        );
        print "  Available methods: " . join(", ", @methods) . "\n";
        
        # Try manual envelope sending
        if ($client->can('_prepare_envelope') && $client->can('_send_envelope')) {
            print "\n📦 Testing manual envelope sending:\n";
            
            my $envelope = $client->_prepare_envelope();
            $envelope->add_item('log', $envelope_item);
            
            my $send_result = $client->_send_envelope($envelope);
            print "  Manual envelope send result: " . ($send_result || 'undefined') . "\n";
        }
    } else {
        print "❌ No client available\n";
    }
} else {
    print "❌ No hub available\n";
}

# Summary
print "\n" . "=" x 50 . "\n";
print "🎯 Diagnostic Summary\n";
print "1. SDK initialized with multiple logging flags\n";
print "2. Standard error message sent (should appear in Issues)\n";
print "3. Manual log record created and inspected\n";
print "4. Direct logger and buffer tested\n";
print "5. Alternative capture_message tested\n";
print "6. Client methods inspected\n";

print "\n📋 What to check in Sentry:\n";
print "• Error from Test 2 should appear in Issues\n";
print "• Message from Test 5 should appear in Issues\n";
print "• If structured logs appear, they should be in Logs section\n";
print "• If no logs appear, the issue might be:\n";
print "  - Sentry project doesn't have structured logging enabled\n";
print "  - Log envelope format needs adjustment\n";
print "  - Logs are being dropped by Sentry backend\n";

print "\n⏱️  Check Sentry dashboard in 1-2 minutes for results\n";