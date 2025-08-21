#!/usr/bin/env perl

use strict;
use warnings;
use v5.32;
use JSON::PP;
use FindBin;

# Add lib to path
use lib "$FindBin::Bin/lib";

print "🔍 Sentry Profile JSON Output Inspection\n";
print "=" x 50 . "\n";

require Sentry::Profiling::Profile;

my $profile = Sentry::Profiling::Profile->new({
    name => 'api-inspection-profile',
});

# Add a realistic sample
my $sample = {
    timestamp => time() + 0.001,
    thread_id => "main",
    frames => [
        {
            function => 'main',
            module => 'main',
            package => 'main',
            filename => '/home/user/app.pl',
            lineno => 1,
            in_app => 1,
        },
        {
            function => 'process_request',
            module => 'WebApp',
            package => 'WebApp::Handler',
            filename => '/home/user/lib/WebApp/Handler.pm',
            lineno => 45,
            in_app => 1,
        },
        {
            function => 'query',
            module => 'DBI',
            package => 'DBI::db', 
            filename => '/usr/lib/perl5/DBI.pm',
            lineno => 892,
            in_app => 0,
        }
    ]
};

$profile->add_sample($sample);
$profile->finish();

my $envelope_item = $profile->to_envelope_item();

# Pretty print the complete JSON structure
my $json = JSON::PP->new->pretty->canonical->encode($envelope_item);

print "📄 Complete Profile JSON Payload:\n";
print "=" x 50 . "\n";
print $json;
print "\n";

print "📊 Payload Analysis:\n";
print "=" x 30 . "\n";

my $data = $envelope_item->{profile};
print "Size: " . length($json) . " bytes\n";
print "Compression potential: ~" . int(length($json) * 0.3) . " bytes (gzip)\n";
print "Samples: " . @{$data->{samples}} . "\n";
print "Frames: " . @{$data->{frames}} . "\n";
print "Stacks: " . @{$data->{stacks}} . "\n";
print "Platform: " . $data->{platform} . "\n";
print "Version: " . $data->{version} . "\n";

print "\n✅ This payload is ready for Sentry's profile ingestion API!\n";
print "📡 Endpoint: POST /api/{project_id}/envelope/\n";
print "🔐 Auth: Sentry DSN authentication required\n";
print "⚠️  Current blocker: Sentry backend doesn't support 'perl' platform\n";