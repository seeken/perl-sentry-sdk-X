#!/usr/bin/env perl

use strict;
use warnings;
use v5.32;
use FindBin;
use lib "$FindBin::Bin/lib";
use Mojo::JSON qw(encode_json decode_json);
use Data::Dumper;

print "🔍 Inspecting Log Payload Format\n";
print "=" x 50 . "\n\n";

my $dsn = $ENV{SENTRY_TEST_DSN} || 'https://bc1b329862866abb9c8f70c5dac940aa@sentry.cgtmigration.com/9';

use Sentry::SDK;
Sentry::SDK->init({
    dsn => $dsn,
    environment => "payload-inspection",
    release => "inspect-1.0",
    debug => 0,
});

# Create a log record manually to inspect it
use Sentry::Logger::LogRecord;
my $record = Sentry::Logger::LogRecord->new(
    level => 'info',
    message => 'Test log message',
    context => {
        custom_field => 'custom_value',
        nested => {
            data => 'nested_value'
        }
    },
);

# Get the envelope item format
my $envelope_item = $record->to_envelope_item();

print "📋 Log Record as Envelope Item:\n";
print "-" x 40 . "\n";
print encode_json($envelope_item);
print "\n\n";

print "🔎 Parsed Structure:\n";
print "-" x 40 . "\n";
print Dumper($envelope_item);
print "\n";

# Now test via logger
my $logger = Sentry::SDK->get_logger();
$logger->info("Logger test message", {
    test_field => 'test_value',
});

# Check what's in the buffer before flushing
my $buffer_records = $logger->buffer->records;
if (@$buffer_records) {
    print "📦 Record in Buffer:\n";
    print "-" x 40 . "\n";
    my $buffered_item = $buffer_records->[0]->to_envelope_item();
    print encode_json($buffered_item);
    print "\n\n";
}

print "✅ Check if you see 'sentry.environment' and 'sentry.release' in attributes\n";