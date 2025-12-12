#!/usr/bin/env perl

use strict;
use warnings;
use v5.32;
use FindBin;
use lib "$FindBin::Bin/lib";

print "🔍 Sentry Self-Hosted Diagnostic\n";
print "=" x 50 . "\n";

my $dsn = $ENV{SENTRY_TEST_DSN} || 'https://bc1b329862866abb9c8f70c5dac940aa@sentry.cgtmigration.com/9';
print "📡 DSN: $dsn\n\n";

# Parse DSN
if ($dsn =~ m{^(https?)://([^@]+)@([^/]+)/(\d+)$}) {
    my ($protocol, $key, $host, $project_id) = ($1, $2, $3, $4);
    print "Protocol: $protocol\n";
    print "Key: $key\n";
    print "Host: $host\n";
    print "Project ID: $project_id\n\n";

    # Test different event types
    print "Testing different event formats...\n";
    print "-" x 40 . "\n";

    use Sentry::SDK;
    Sentry::SDK->init({
        dsn => $dsn,
        environment => "diagnostic",
        release => "diagnostic-1.0",
        debug => 1,
        traces_sample_rate => 0,  # Disable tracing
    });

    # Test 1: Standard exception (should always work)
    print "\n1️⃣ Testing standard exception...\n";
    eval {
        die "Diagnostic test exception - should appear in Issues";
    };
    if ($@) {
        Sentry::SDK->capture_exception($@);
        print "✅ Exception sent\n";
    }

    # Test 2: Message event
    print "\n2️⃣ Testing message event...\n";
    Sentry::SDK->capture_message("Diagnostic test message", 'warning');
    print "✅ Message sent\n";

    # Test 3: Custom event with logger field
    print "\n3️⃣ Testing custom event with logger field...\n";
    my $hub = Sentry::SDK->get_current_hub();
    if ($hub && $hub->client) {
        my $event = {
            timestamp => time(),
            level => 'info',
            logger => 'diagnostic-logger',
            platform => 'perl',
            message => {
                formatted => 'Diagnostic custom event with logger field'
            },
            extra => {
                test_type => 'custom_event',
                diagnostic => 1
            }
        };

        $hub->client->capture_event($event);
        print "✅ Custom event sent\n";
    }

    # Test 4: Breadcrumb with message
    print "\n4️⃣ Testing breadcrumb + message...\n";
    Sentry::SDK->add_breadcrumb({
        message => 'Diagnostic breadcrumb',
        category => 'diagnostic',
        level => 'info',
        data => {
            test => 'breadcrumb_test'
        }
    });
    Sentry::SDK->capture_message("Message with breadcrumb", 'info');
    print "✅ Breadcrumb + message sent\n";

    print "\n" . "=" x 50 . "\n";
    print "📋 What to check:\n\n";

    print "1. Check Sentry web logs:\n";
    print "   docker logs sentry-web --tail 100 | grep '$project_id'\n\n";

    print "2. Check worker logs:\n";
    print "   docker logs sentry-worker --tail 100 | grep -E '(event|envelope|log)'\n\n";

    print "3. Check nginx/relay logs (if applicable):\n";
    print "   docker logs sentry-relay --tail 100\n\n";

    print "4. Check project settings:\n";
    print "   - Go to: $protocol://$host/settings/projects/\n";
    print "   - Verify project ID $project_id exists\n";
    print "   - Check if 'Store Native Crashes' is enabled\n";
    print "   - Check rate limits\n\n";

    print "5. Check for these specific event IDs in logs:\n";
    print "   - Look for event IDs that were returned (shown in debug output)\n\n";

    print "6. Direct database check (if you have access):\n";
    print "   docker exec -it sentry-postgres psql -U postgres sentry -c \"SELECT COUNT(*) FROM sentry_message WHERE project_id=$project_id;\"\n\n";

} else {
    print "❌ Invalid DSN format\n";
}

print "💡 Common issues:\n";
print "• Events sent as 'log' type are not supported in older Sentry versions\n";
print "• Rate limiting or quota exceeded\n";
print "• Project doesn't exist or wrong project ID\n";
print "• Clock skew between client and server\n";
print "• Firewall/proxy blocking requests\n";
print "• Sentry worker backlog\n";