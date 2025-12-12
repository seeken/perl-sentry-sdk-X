#!/usr/bin/env perl

use strict;
use warnings;
use v5.32;
use FindBin;
use lib "$FindBin::Bin/lib";

print "🎯 Project-Specific Sentry Test\n";
print "=" x 50 . "\n";

# Check which project to use
my $dsn = $ENV{SENTRY_TEST_DSN} || 'https://bc1b329862866abb9c8f70c5dac940aa@sentry.cgtmigration.com/9';

# Parse DSN to show project ID
if ($dsn =~ m{/(\d+)$}) {
    my $project_id = $1;
    print "📌 Sending to Project ID: $project_id\n";
    print "📡 DSN: $dsn\n\n";

    print "⚠️  Make sure you're viewing Project $project_id in Sentry UI!\n";
    print "   URL should be: https://sentry.cgtmigration.com/organizations/YOUR_ORG/projects/PROJECT_NAME/?project=$project_id\n\n";
} else {
    die "Invalid DSN format\n";
}

use Sentry::SDK;
Sentry::SDK->init({
    dsn => $dsn,
    environment => "project-test",
    release => "project-test-1.0",
    debug => 1,
});

print "✅ SDK initialized\n\n";

# Send a simple exception first (these always work)
print "1️⃣ Sending test exception...\n";
eval {
    die "Project test exception - Check if this appears in Project $1";
};
if ($@) {
    Sentry::SDK->capture_exception($@);
    print "✅ Exception sent\n\n";
}

# Send a message
print "2️⃣ Sending test message...\n";
Sentry::SDK->capture_message("Project test message - Check Project $1", 'warning');
print "✅ Message sent\n\n";

# Get logger and send structured log with clean format
print "3️⃣ Sending structured log with clean format...\n";
my $logger = Sentry::SDK->get_logger();

# Use clean field names (no 'sentry.' prefix)
$logger->error("Structured log test for project verification", {
    test_id => "project_" . time(),
    component => "test_script",
    action => "verify_project",
    project_check => $1,
    user_note => "This should appear in project $1",
    metadata => {
        version => "1.0",
        test_type => "project_verification"
    }
});

print "✅ Structured log sent\n\n";

# Flush
print "🔄 Flushing logs...\n";
$logger->buffer->flush();

print "\n" . "=" x 50 . "\n";
print "📋 Next Steps:\n\n";
print "1. Go to your Sentry UI\n";
print "2. Make sure you're viewing PROJECT $1 (not project 1)\n";
print "3. Check the Issues/Events section\n";
print "4. Filter by environment: 'project-test'\n";
print "5. Look for the exception and message first\n\n";

print "If you see the exception but not the logs, try checking:\n";
print "• docker logs sentry-worker | grep 'project_$1'\n";
print "• The Issues section (logs might appear as events)\n";
print "• Remove any date/time filters in the UI\n";