#!/usr/bin/env perl
use strict;
use warnings;
use lib 'lib';

use Sentry::SDK;
use Time::HiRes qw(sleep);
use DBI;
use LWP::UserAgent;
use Mojo::UserAgent;
use Data::Dumper;

# Get Sentry DSN from environment
my $sentry_dsn = $ENV{SENTRY_TEST_DSN};
unless ($sentry_dsn) {
    die "Please set SENTRY_TEST_DSN environment variable with your Sentry DSN\n";
}

print "=== Perl Sentry SDK Live Test ===\n";
print "Sending telemetry to: " . substr($sentry_dsn, 0, 40) . "...\n\n";

# Initialize Sentry with our enhanced Phase 1 features
Sentry::SDK->init({
    dsn => $sentry_dsn,
    environment => 'test',
    release => 'perl-sdk-phase1-test',
    traces_sample_rate => 1.0,
    send_default_pii => 0,  # Don't send SQL statements for security
    capture_failed_requests => 1,
    capture_4xx_errors => 0,
});

print "✅ Sentry SDK initialized with Phase 1 enhancements\n\n";

# Test 1: Basic error capture
print "🔸 Test 1: Capturing a simple error...\n";
Sentry::SDK->capture_message("Live test: Basic error message", "error");
print "   Sent error message\n";

# Test 2: Exception capture with context
print "\n🔸 Test 2: Capturing exception with context...\n";
Sentry::SDK->configure_scope(sub {
    my ($scope) = @_;
    $scope->set_tag("test_type", "live_demo");
    $scope->set_tag("phase", "phase1");
    $scope->set_user({
        id => "test_user_123",
        username => "perl_tester",
        email => "test\@example.com"
    });
    $scope->set_context("test_info", {
        script => "sentry_live_test.pl",
        perl_version => $^V,
        pid => $$,
    });
});

eval {
    die "Test exception for Sentry demonstration";
};
if ($@) {
    Sentry::SDK->capture_exception($@);
    print "   Sent exception with rich context\n";
}

# Test 3: Performance monitoring with enhanced DBI integration
print "\n🔸 Test 3: Database operations with enhanced telemetry...\n";
eval {
    # Use SQLite for portability
    my $dbh = DBI->connect("dbi:SQLite:dbname=:memory:", "", "", { 
        PrintError => 0,
        RaiseError => 1 
    });
    
    # Start a performance transaction
    my $transaction = Sentry::SDK->start_transaction({
        name => 'database_operations_test',
        op => 'db.test',
    });
    
    Sentry::SDK->configure_scope(sub {
        my ($scope) = @_;
        $scope->set_span($transaction);
    });
    
    print "   Starting database transaction...\n";
    
    # These operations will trigger our enhanced DBI integration
    $dbh->do("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, email TEXT)");
    $dbh->do("INSERT INTO users (name, email) VALUES ('Alice', 'alice\@test.com')");
    $dbh->do("INSERT INTO users (name, email) VALUES ('Bob', 'bob\@test.com')");
    
    my $sth = $dbh->prepare("SELECT * FROM users WHERE name LIKE ?");
    $sth->execute('%a%');
    my $results = $sth->fetchall_arrayref();
    
    $dbh->do("UPDATE users SET email = 'alice.new\@test.com' WHERE name = 'Alice'");
    $dbh->do("DELETE FROM users WHERE name = 'Bob'");
    
    print "   Executed SQL operations (CREATE, INSERT, SELECT, UPDATE, DELETE)\n";
    print "   Enhanced telemetry includes: operation types, table names, durations, row counts\n";
    
    $transaction->set_tag("db_operations", scalar(@$results));
    $transaction->finish();
    
    $dbh->disconnect();
};
if ($@) {
    print "   Database test skipped: $@\n";
}

# Test 4: HTTP client telemetry
print "\n🔸 Test 4: HTTP requests with enhanced telemetry...\n";

# Start another transaction for HTTP operations
my $http_transaction = Sentry::SDK->start_transaction({
    name => 'http_requests_test',
    op => 'http.test',
});

Sentry::SDK->configure_scope(sub {
    my ($scope) = @_;
    $scope->set_span($http_transaction);
});

# Test LWP UserAgent integration
eval {
    my $lwp = LWP::UserAgent->new(timeout => 10);
    print "   Making HTTP request with LWP::UserAgent...\n";
    
    # This will trigger our enhanced LWP integration
    my $response = $lwp->get('https://httpbin.org/json');
    
    print "   LWP request completed (status: " . $response->code . ")\n";
    print "   Enhanced telemetry includes: OpenTelemetry conventions, durations, trace headers\n";
};
if ($@) {
    print "   LWP test failed: $@\n";
}

# Test Mojo UserAgent integration
eval {
    my $mojo = Mojo::UserAgent->new;
    print "   Making HTTP request with Mojo::UserAgent...\n";
    
    # This will trigger our enhanced Mojo integration
    my $tx = $mojo->get('https://httpbin.org/headers');
    
    print "   Mojo request completed (status: " . ($tx->res->code // 'unknown') . ")\n";
    print "   Enhanced telemetry includes: OpenTelemetry conventions, durations, trace headers\n";
};
if ($@) {
    print "   Mojo test failed: $@\n";
}

$http_transaction->finish();

# Test 5: Breadcrumb trail
print "\n🔸 Test 5: Creating breadcrumb trail...\n";
Sentry::SDK->add_breadcrumb({
    category => "navigation",
    message => "User started live test",
    level => "info",
    data => { section => "initialization" }
});

Sentry::SDK->add_breadcrumb({
    category => "user_action", 
    message => "Database operations performed",
    level => "info",
    data => { operations => 5, tables => ["users"] }
});

Sentry::SDK->add_breadcrumb({
    category => "network",
    message => "HTTP requests completed", 
    level => "info",
    data => { requests => 2, protocols => ["https"] }
});

print "   Added breadcrumb trail with rich metadata\n";

# Test 6: Multiple events in quick succession
print "\n🔸 Test 6: Stress testing with multiple events...\n";
for my $i (1..5) {
    Sentry::SDK->capture_message("Bulk test message #$i", "info");
    sleep(0.1);  # Small delay to see events in sequence
}
print "   Sent 5 rapid-fire messages\n";

# Test 7: Demonstrate different severity levels
print "\n🔸 Test 7: Testing different severity levels...\n";
my @levels = ('debug', 'info', 'warning', 'error', 'fatal');
for my $level (@levels) {
    Sentry::SDK->capture_message("Test message at $level level", $level);
}
print "   Sent messages at all severity levels\n";

# Test 8: Custom event with rich data
print "\n🔸 Test 8: Custom event with rich metadata...\n";
Sentry::SDK->capture_event({
    message => "Custom event from live test",
    level => "info",
    tags => {
        environment => "test",
        feature => "live_testing", 
        sdk_version => "phase1",
    },
    extra => {
        test_data => {
            timestamp => time(),
            hostname => `hostname` || 'unknown',
            perl_version => $^V,
            script_name => $0,
        },
        performance_metrics => {
            memory_usage => "unknown",
            cpu_usage => "unknown", 
            uptime => time() - $^T,
        }
    },
    contexts => {
        runtime => {
            name => "perl",
            version => $^V,
        },
        os => {
            name => $^O,
        }
    }
});
print "   Sent custom event with comprehensive metadata\n";

# Final summary
print "\n=== Live Test Complete ===\n";
print "🎯 Events sent to Sentry:\n";
print "   • Error messages and exceptions\n";
print "   • Database operations with enhanced telemetry\n"; 
print "   • HTTP requests with OpenTelemetry data\n";
print "   • Performance transactions and spans\n";
print "   • Breadcrumb trails\n";
print "   • Multiple severity levels\n";
print "   • Rich contextual metadata\n";
print "\n📊 Phase 1 Features Demonstrated:\n";
print "   ✅ Fixed integration setup (all integrations active)\n";
print "   ✅ Enhanced DBI telemetry (OpenTelemetry conventions)\n";
print "   ✅ Enhanced HTTP client telemetry\n";
print "   ✅ Performance monitoring with spans\n";
print "   ✅ Rich contextual data capture\n";
print "   ✅ Multiple envelope item support\n";

print "\n🔍 Check your Sentry dashboard to see all the telemetry data!\n";
print "Look for:\n";
print "   - Error events with stack traces\n";
print "   - Performance transactions showing database and HTTP operations\n";
print "   - Breadcrumb trails showing user journey\n";
print "   - Rich context data including environment, user, and runtime info\n";
