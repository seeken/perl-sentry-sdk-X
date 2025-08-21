#!/usr/bin/env perl

use strict;
use warnings;
use v5.32;
use JSON::PP;
use Data::Dumper;
use Time::HiRes;

# Add lib to path
use lib 'lib';

use Sentry::SDK;
use Sentry::Profiling;

print "🔍 Profile Format Debug Test\n";
print "============================\n\n";

# Initialize SDK
Sentry::SDK->init({
    dsn => 'https://bc1b329862866abb9c8f70c5dac940aa@sentry.cgtmigration.com/9',
    environment => 'production',
    enable_profiling => 1,
    traces_sample_rate => 1.0,
    profiles_sample_rate => 1.0,
    debug => 1,
});

# Get profiler
my $profiler = Sentry::SDK->get_profiler();
unless ($profiler) {
    die "❌ No profiler available";
}

print "✅ SDK and profiler initialized\n\n";

# Start manual profiling
print "📊 Starting manual profiling...\n";
my $profile = $profiler->start_profiler({ 
    name => 'format-debug-test',
    duration_seconds => 1
});

unless ($profile) {
    die "❌ Failed to start profiling";
}

print "✅ Profiling started\n";

# Do some work to generate samples
print "💻 Generating workload...\n";
for my $i (1..5) {
    # CPU intensive work
    my $sum = 0;
    for my $j (1..50000) {
        $sum += sqrt($j) * sin($j);
    }
    
    # Let the automatic sampling work, no need to manually trigger
    print "   Batch $i completed (sum: " . int($sum) . ")\n";
}

sleep(0.1); # Let automatic sampling fire a few times

print "🔄 Stopping profiler...\n";
my $final_profile = $profiler->stop_profiler();

unless ($final_profile) {
    die "❌ No profile returned from stop_profiler";
}

print "✅ Profiling stopped\n\n";

# Examine profile structure
print "📋 Profile Analysis:\n";
print "   Duration: " . $final_profile->get_duration() . "s\n";
print "   Sample count: " . $final_profile->get_sample_count() . "\n";
my $stats = $final_profile->get_stats();
print "   Unique frames: " . $stats->{unique_frames} . "\n";
print "   Unique stacks: " . $stats->{unique_stacks} . "\n\n";

# Generate envelope to see the exact format
print "📦 Generating envelope...\n";
eval {
    my $envelope_data = $final_profile->to_envelope_item();
    
    if ($envelope_data) {
        print "✅ Envelope generated successfully\n";
        print "   Type: " . ($envelope_data->{type} || 'unknown') . "\n";
        print "   Has profile data: " . ($envelope_data->{profile} ? "YES" : "NO") . "\n";
        
        if ($envelope_data->{profile}) {
            my $prof_data = $envelope_data->{profile};
            print "   Profile structure:\n";
            print "     - version: " . ($prof_data->{version} || 'missing') . "\n";
            print "     - platform: " . ($prof_data->{platform} || 'missing') . "\n";
            print "     - runtime: " . ($prof_data->{runtime}->{name} || 'missing') . " " . ($prof_data->{runtime}->{version} || '') . "\n";
            print "     - device architecture: " . ($prof_data->{device}->{architecture} || 'missing') . "\n";
            print "     - samples: " . (ref($prof_data->{samples}) eq 'ARRAY' ? scalar(@{$prof_data->{samples}}) : 'not array') . "\n";
            print "     - frames: " . (ref($prof_data->{frames}) eq 'ARRAY' ? scalar(@{$prof_data->{frames}}) : 'not array') . "\n";
            print "     - stacks: " . (ref($prof_data->{stacks}) eq 'ARRAY' ? scalar(@{$prof_data->{stacks}}) : 'not array') . "\n";
            
            # Show first sample structure
            if (ref($prof_data->{samples}) eq 'ARRAY' && @{$prof_data->{samples}}) {
                my $first_sample = $prof_data->{samples}->[0];
                print "     - first sample keys: " . join(", ", sort keys %$first_sample) . "\n";
            }
            
            # Show first frame structure  
            if (ref($prof_data->{frames}) eq 'ARRAY' && @{$prof_data->{frames}}) {
                my $first_frame = $prof_data->{frames}->[0];
                print "     - first frame keys: " . join(", ", sort keys %$first_frame) . "\n";
            }
        }
        
        # Save raw envelope data for inspection
        my $json_str = JSON::PP->new->pretty->canonical->encode($envelope_data);
        
        open my $fh, '>', 'debug_profile_envelope.json' or die "Can't write envelope: $!";
        print $fh $json_str;
        close $fh;
        
        print "💾 Full envelope saved to: debug_profile_envelope.json\n";
        print "📏 Envelope size: " . length($json_str) . " bytes\n";
        
    } else {
        print "❌ No envelope data generated\n";
    }
};

if ($@) {
    print "❌ Error generating envelope: $@\n";
}

print "\n🎯 Debug Complete\n";
print "Next steps:\n";
print "1. Check debug_profile_envelope.json for format issues\n";
print "2. Verify Sentry project has profiling enabled\n";
print "3. Check if SDK version/platform is supported\n";