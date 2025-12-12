#!/usr/bin/env perl

use strict;
use warnings;
use v5.32;
use FindBin;
use lib "$FindBin::Bin/lib";

print "✅ Simple Working Test\n";
print "=" x 50 . "\n";

my $dsn = $ENV{SENTRY_TEST_DSN} || 'https://bc1b329862866abb9c8f70c5dac940aa@sentry.cgtmigration.com/9';
my $project_id = $1 if $dsn =~ m{/(\d+)$};

print "📡 DSN: $dsn\n";
print "📌 Project ID: $project_id\n\n";

use Sentry::SDK;
Sentry::SDK->init({
    dsn => $dsn,
    environment => "simple-working",
    release => "simple-1.0",
    debug => 0,
});

my $test_id = time();

# Test 1: Simple message (should work)
print "1️⃣ Simple message: ";
Sentry::SDK->capture_message("Simple test $test_id", 'info');
print "✅\n";

# Test 2: Message with scope data
print "2️⃣ Message with extra data: ";
Sentry::SDK->with_scope(sub {
    my $scope = shift;
    $scope->set_tag('test_id', $test_id);
    $scope->set_extra('purpose', 'testing');
    $scope->set_extra('structured_data', {
        key1 => 'value1',
        key2 => 'value2',
        nested => {
            inner => 'data'
        }
    });

    Sentry::SDK->capture_message("Message with structured data $test_id", 'warning');
});
print "✅\n";

# Test 3: Use logger
print "3️⃣ Logger test: ";
my $logger = Sentry::SDK->get_logger();
$logger->error("Logger error test $test_id", {
    test_id => $test_id,
    component => 'test',
    data => {
        field1 => 'value1',
        field2 => 'value2'
    }
});
$logger->buffer->flush();
print "✅\n";

# Test 4: Exception (always works)
print "4️⃣ Exception: ";
eval { die "Test exception $test_id" };
if ($@) {
    Sentry::SDK->capture_exception($@);
    print "✅\n";
}

print "\n" . "=" x 50 . "\n";
print "📋 Check Project $project_id in Sentry:\n";
print "• Environment: 'simple-working'\n";
print "• Look for test_id: $test_id\n";
print "• Click on events to see structured data in 'Extra' section\n";