#!/usr/bin/env perl

use strict;
use warnings;
use v5.32;
use FindBin;
use lib "$FindBin::Bin/lib";

print "🎯 Simple Event Format Test\n";
print "=" x 50 . "\n";

my $dsn = $ENV{SENTRY_TEST_DSN} || 'https://bc1b329862866abb9c8f70c5dac940aa@sentry.cgtmigration.com/9';
print "📡 DSN: $dsn\n\n";

# Parse project ID
my $project_id = $1 if $dsn =~ m{/(\d+)$};
print "📌 Project ID: $project_id\n\n";

use Sentry::SDK;
Sentry::SDK->init({
    dsn => $dsn,
    environment => "simple-test",
    release => "simple-1.0",
    debug => 0,  # Less verbose
});

print "Sending test events...\n";
print "-" x 30 . "\n";

# Test 1: Use capture_message (this should always work)
print "1️⃣ capture_message: ";
Sentry::SDK->capture_message("Simple test message from Perl SDK", 'info', {
    tags => {
        component => 'test',
        format => 'simple',
    },
    extra => {
        test_id => time(),
        purpose => 'verify_logging',
    }
});
print "✅\n";

# Test 2: capture_message with error level
print "2️⃣ capture_message (error): ";
Sentry::SDK->capture_message("Error level message from Perl SDK", 'error', {
    extra => {
        error_code => 'TEST_001',
        details => 'This is an error-level message',
    }
});
print "✅\n";

# Test 3: Use the hub directly to send a custom event
print "3️⃣ Custom event via hub: ";
my $hub = Sentry::SDK->get_current_hub();
if ($hub && $hub->client) {
    my $event = {
        message => 'Custom event sent directly',
        level => 'warning',
        timestamp => time(),
        platform => 'perl',
        tags => {
            custom => 'true',
        },
        extra => {
            method => 'direct_hub',
            test_number => 3,
        },
    };
    $hub->client->capture_event($event);
    print "✅\n";
}

# Test 4: Exception for comparison
print "4️⃣ Exception (for comparison): ";
eval {
    die "Test exception - should definitely appear";
};
if ($@) {
    Sentry::SDK->capture_exception($@);
    print "✅\n";
}

print "\n" . "=" x 50 . "\n";
print "✅ All events sent!\n\n";

print "📋 Check Sentry Project $project_id:\n";
print "• Environment: 'simple-test'\n";
print "• You should see at least 4 events\n";
print "• The exception will definitely appear\n";
print "• Messages should appear as events\n\n";

print "🔍 If you don't see the messages:\n";
print "1. Make sure you're viewing project $project_id\n";
print "2. Remove any filters in the UI\n";
print "3. Check 'Resolved' and 'Ignored' tabs too\n";
print "4. Try the Discover or Events section\n";