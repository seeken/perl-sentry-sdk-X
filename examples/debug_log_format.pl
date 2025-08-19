#!/usr/bin/env perl

use strict;
use warnings;
use lib 'lib';

use Sentry::SDK;
use Sentry::Logger::LogRecord;
use Mojo::JSON qw(encode_json);
use Data::Dumper;

print "Debug: Testing Log Format\n";
print "=" x 40, "\n";

# Create a sample log record
my $record = Sentry::Logger::LogRecord->new(
    level => 'info',
    message => 'Sample log message',
    context => {
        user_id => 12345,
        environment => 'test',
        component => 'debug',
    },
);

print "1. Log Record Internal Structure:\n";
print Dumper($record);

print "\n2. Log Record to_hash():\n";
my $hash = $record->to_hash();
print Dumper($hash);

print "\n3. Log Record to_envelope_item():\n";
my $envelope_item = $record->to_envelope_item();
print Dumper($envelope_item);

print "\n4. JSON-encoded envelope item:\n";
print encode_json($envelope_item) . "\n";

print "\n5. Testing with trace context:\n";
$record->trace_id('abc123trace');
$record->span_id('def456span');
my $envelope_with_trace = $record->to_envelope_item();
print encode_json($envelope_with_trace) . "\n";

print "\nFormat verification complete!\n";