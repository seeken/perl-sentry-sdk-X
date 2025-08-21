#!/usr/bin/env perl
use strict;
use warnings;
use lib 'lib';

use Sentry::Profiling;
use Sentry::Profiling::StackSampler;
use Sentry::Profiling::Profile;

print "Testing basic profiling components...\n";

# Test 1: Profile creation
my $profile = Sentry::Profiling::Profile->new(
    name => 'test-profile'
);
print "✓ Profile created: " . $profile->name . "\n";

# Test 2: Manual sample addition
$profile->add_sample({
    timestamp => time(),
    thread_id => "$$",
    frames => [
        {
            package => 'main',
            filename => 'test.pl',
            lineno => 10,
            function => 'main',
            in_app => 1
        },
        {
            package => 'TestModule',
            filename => 'lib/TestModule.pm',
            lineno => 25,
            function => 'test_function',
            in_app => 1
        }
    ]
});

print "✓ Sample added manually\n";

# Test 3: Profile stats
$profile->finish();
my $stats = $profile->get_stats();
print "✓ Profile stats: samples=" . $stats->{sample_count} . ", frames=" . $stats->{unique_frames} . "\n";

# Test 4: Envelope creation
my $envelope = $profile->to_envelope_item();
print "✓ Envelope created, type: " . $envelope->{type} . "\n";

# Test 5: StackSampler manual sampling
my $sampler = Sentry::Profiling::StackSampler->new();
my $test_profile = Sentry::Profiling::Profile->new(name => 'sampler-test');

$sampler->_active_profile($test_profile);
$sampler->sample_once();  # Manual sampling

$test_profile->finish();
my $sampler_stats = $test_profile->get_stats();
print "✓ Sampler test: samples=" . $sampler_stats->{sample_count} . "\n";

print "All basic tests passed!\n";