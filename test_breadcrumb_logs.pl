#!/usr/bin/env perl

use strict;
use warnings;
use v5.32;
use FindBin;
use lib "$FindBin::Bin/lib";

print "🍞 Testing Logs as Breadcrumbs\n";
print "=" x 50 . "\n";

my $dsn = $ENV{SENTRY_TEST_DSN} || 'https://bc1b329862866abb9c8f70c5dac940aa@sentry.cgtmigration.com/9';

use Sentry::SDK;
Sentry::SDK->init({
    dsn => $dsn,
    environment => "breadcrumb-test",
    release => "breadcrumb-1.0",
    debug => 0,
});

print "Adding logs as breadcrumbs...\n\n";

# Add multiple log entries as breadcrumbs
Sentry::SDK->add_breadcrumb({
    timestamp => time(),
    category => 'log',
    level => 'info',
    message => 'Application started',
    data => {
        component => 'main',
        version => '1.0',
    }
});

Sentry::SDK->add_breadcrumb({
    timestamp => time(),
    category => 'log',
    level => 'debug',
    message => 'Connected to database',
    data => {
        host => 'db.example.com',
        port => 5432,
        pool_size => 10,
    }
});

Sentry::SDK->add_breadcrumb({
    timestamp => time(),
    category => 'log',
    level => 'info',
    message => 'Processing user request',
    data => {
        user_id => 12345,
        action => 'create_order',
        items_count => 3,
    }
});

Sentry::SDK->add_breadcrumb({
    timestamp => time(),
    category => 'log',
    level => 'warning',
    message => 'Slow query detected',
    data => {
        query => 'SELECT * FROM large_table',
        duration_ms => 2500,
        rows_returned => 10000,
    }
});

Sentry::SDK->add_breadcrumb({
    timestamp => time(),
    category => 'log',
    level => 'error',
    message => 'Failed to send email',
    data => {
        recipient => 'user@example.com',
        error => 'SMTP timeout',
        retry_count => 3,
    }
});

# Now trigger an event that will include all the breadcrumbs
print "Triggering event with breadcrumb trail...\n";

# Option 1: Send a message
Sentry::SDK->capture_message(
    "Event with full breadcrumb log trail",
    'error',
    {
        extra => {
            trigger => 'test_completion',
            purpose => 'show_breadcrumb_logs',
        }
    }
);

print "✅ Sent event with breadcrumbs\n\n";

# Option 2: Trigger an exception
eval {
    die "Exception with breadcrumb trail";
};
if ($@) {
    Sentry::SDK->capture_exception($@);
    print "✅ Sent exception with breadcrumbs\n\n";
}

print "=" x 50 . "\n";
print "📋 CHECK IN SENTRY:\n\n";
print "1. Look for 'Event with full breadcrumb log trail'\n";
print "2. Click on the event\n";
print "3. Look for the 'Breadcrumbs' section\n";
print "4. You should see a timeline of all the log entries\n";
print "5. Each breadcrumb will have its structured data\n\n";

print "💡 BREADCRUMBS ADVANTAGE:\n";
print "• Shows a timeline of what happened before the event\n";
print "• Great for debugging issues\n";
print "• Structured data is preserved\n";
print "• Works with all Sentry versions\n";