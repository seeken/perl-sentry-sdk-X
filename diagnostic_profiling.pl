#!/usr/bin/env perl

use strict;
use warnings;
use feature 'say';
use Time::HiRes qw(sleep time);

use lib 'lib';
use Sentry::SDK;

my $dsn = 'https://bc1b329862866abb9c8f70c5dac940aa@sentry.cgtmigration.com/9';

say "🔍 DIAGNOSTIC: Profiling Sampling Flow";
say "=" x 40;

# Initialize SDK with verbose logging
Sentry::SDK->init({
    dsn => $dsn,
    traces_sample_rate => 1.0,
    profiles_sample_rate => 1.0,
    enable_profiling => 1,
    sampling_interval_us => 5000,  # 5ms
    adaptive_sampling => 0,
    debug => 1,
});

my $profiler = Sentry::SDK->get_profiler();

# Step 1: Check profiler state
say "\n📋 Step 1: Profiler State Check";
say "-" x 35;
say "Profiler class: " . ref($profiler);
say "Enable profiling: " . ($profiler->enable_profiling ? "YES" : "NO");
say "Sample rate: " . ($profiler->profiles_sample_rate * 100) . "%";
say "Session sample rate: " . ($profiler->profile_session_sample_rate * 100) . "%";
say "Currently profiling: " . ($profiler->is_profiling_active ? "YES" : "NO");

# Step 2: Test sampling decision logic
say "\n📋 Step 2: Sampling Decision Test";
say "-" x 35;

# Add debug hook to see what _should_start_profile returns
{
    no strict 'refs';
    my $original_should = \&Sentry::Profiling::_should_start_profile;
    *Sentry::Profiling::_should_start_profile = sub {
        my $result = $original_should->(@_);
        say "   _should_start_profile returned: " . ($result ? "TRUE" : "FALSE");
        return $result;
    };
}

# Test starting profiler
say "Attempting to start profiler...";
my $profile = $profiler->start_profiler({
    name => 'diagnostic-test'
});

if ($profile) {
    say "✅ Profiler started successfully";
    say "   Profile name: " . $profile->name;
} else {
    say "❌ Failed to start profiler";
    exit 1;
}

# Step 3: Check sampler state
say "\n📋 Step 3: StackSampler State Check";
say "-" x 38;

my $sampler = $profiler->_sampler;
say "Sampler class: " . ref($sampler);
say "Is sampling: " . ($sampler->is_sampling ? "YES" : "NO");
say "Sample count so far: " . $sampler->get_sample_count;

# Step 4: Test alarm mechanism in context
say "\n📋 Step 4: Alarm Mechanism Test";
say "-" x 32;

my $alarm_fired = 0;
my $original_handler = $SIG{ALRM};

# Check what's actually in the ALRM handler
if (ref($SIG{ALRM}) eq 'CODE') {
    say "✅ SIGALRM handler is set (CODE ref)";
} elsif (defined $SIG{ALRM}) {
    say "⚠️  SIGALRM handler is set but not a CODE ref: " . $SIG{ALRM};
} else {
    say "❌ No SIGALRM handler set";
}

# Let's manually trigger what should happen during sampling
say "\nTesting manual sample trigger...";
if ($sampler->can('sample_once')) {
    $sampler->sample_once();
    say "Triggered manual sample";
    
    my $new_count = $sampler->get_sample_count;
    say "Sample count after manual trigger: $new_count";
    
    if ($new_count > 0) {
        say "✅ Manual sampling works!";
    } else {
        say "❌ Manual sampling failed";
    }
} else {
    say "❌ Sampler doesn't have sample_once method";
}

# Step 5: Generate work and monitor sampling
say "\n📋 Step 5: Work Generation and Monitoring";
say "-" x 40;

say "Generating work for 2 seconds with monitoring...";

my $work_start = time();
my $initial_count = $sampler->get_sample_count;

# Do work while monitoring sample count
while (time() - $work_start < 2.0) {
    # CPU work
    my $result = 0;
    for my $i (1..500) {
        $result += fibonacci($i % 15);
    }
    
    # Check sample count periodically
    my $current_count = $sampler->get_sample_count;
    if ($current_count > $initial_count) {
        say "   📊 Sample collected! Total: $current_count";
        $initial_count = $current_count;
    }
    
    sleep(0.01);  # 10ms intervals
}

# Final sample count
my $final_count = $sampler->get_sample_count;
say "Final sample count: $final_count";

# Step 6: Stop profiler and check results
say "\n📋 Step 6: Stop Profiler and Results";
say "-" x 37;

say "Stopping profiler...";
my $stopped_profile = $profiler->stop_profiler();

if ($stopped_profile) {
    my $stats = $stopped_profile->get_stats();
    say "✅ Profiler stopped successfully";
    say "   Final sample count: " . $stats->{sample_count};
    say "   Unique frames: " . $stats->{unique_frames};
    say "   Duration: " . sprintf("%.3fs", $stats->{duration} || 0);
    
    if ($stats->{sample_count} > 0) {
        say "🎉 SUCCESS: Profiling collected samples!";
        
        # Test envelope generation
        my $envelope_item = $stopped_profile->to_envelope_item();
        if ($envelope_item && $envelope_item->{profile}) {
            my $profile_data = $envelope_item->{profile};
            say "   Profile envelope contains:";
            say "     - Samples: " . scalar(@{$profile_data->{samples} || []});
            say "     - Frames: " . scalar(@{$profile_data->{frames} || []});
            say "     - Stacks: " . scalar(@{$profile_data->{stacks} || []});
            
            say "\n✅ DIAGNOSTIC COMPLETE: Profiling is working correctly!";
            say "The issue may be in the live test environment or specific conditions.";
        } else {
            say "❌ Envelope generation failed";
        }
    } else {
        say "❌ PROBLEM: No samples were collected";
        say "This indicates an issue with the signal-based sampling mechanism.";
        
        # Additional diagnostics
        say "\n🔍 Additional Diagnostics:";
        say "   - Check if SIGALRM is being blocked";
        say "   - Verify alarm() calls are working";
        say "   - Test in different environment";
    }
} else {
    say "❌ Failed to stop profiler";
}

sub fibonacci {
    my ($n) = @_;
    return $n if $n <= 1;
    return fibonacci($n - 1) + fibonacci($n - 2);
}

__END__