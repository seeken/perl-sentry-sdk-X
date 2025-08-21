#!/usr/bin/env perl

use strict;
use warnings;
use feature 'say';
use Time::HiRes qw(time sleep usleep);

use lib 'lib';
use Sentry::SDK;

my $dsn = 'https://bc1b329862866abb9c8f70c5dac940aa@sentry.cgtmigration.com/9';

say "🔍 Debugging Profiling Sample Collection";
say "DSN: $dsn";
say "=" x 50;

# Initialize with more aggressive profiling settings
Sentry::SDK->init({
    dsn => $dsn,
    traces_sample_rate => 1.0,
    profiles_sample_rate => 1.0,
    enable_profiling => 1,
    sampling_interval_us => 1000,    # 1ms - very frequent
    adaptive_sampling => 0,          # Disabled for testing
    debug => 1,
});

say "✅ SDK initialized with aggressive profiling settings";

# Get profiler to inspect it directly
my $profiler = Sentry::SDK->get_profiler();
say "Profiler class: " . ref($profiler);

# Test the StackSampler directly
say "\n🔬 Testing StackSampler directly";
say "-" x 35;

require Sentry::Profiling::StackSampler;
my $sampler = Sentry::Profiling::StackSampler->new(
    interval_us => 1000,  # 1ms
);

require Sentry::Profiling::Profile;
my $profile = Sentry::Profiling::Profile->new();

say "Created sampler and profile";

# Start sampling manually
$sampler->start($profile);
say "Started sampler";

# Do some CPU work to generate samples
say "Generating CPU work...";
for my $i (1..1000) {
    my $result = 0;
    for my $j (1..100) {
        $result += $j * $j;
    }
    if ($i % 100 == 0) {
        usleep(1000);  # 1ms delay to allow sampling
    }
}

# Also try triggering a sample manually
say "Triggering manual sample...";
$sampler->sample_once();

sleep(0.1);  # Let any pending samples complete

# Stop sampling
$sampler->stop();
say "Stopped sampler";

# Check profile stats
my $stats = $profile->get_stats();
say "Profile statistics:";
say "  - Sample count: " . $stats->{sample_count};
say "  - Unique frames: " . $stats->{unique_frames};
say "  - Unique stacks: " . $stats->{unique_stacks};
say "  - Duration: " . sprintf("%.3fs", $stats->{duration} || 0);

if ($stats->{sample_count} > 0) {
    say "✅ Direct sampling worked!";
    
    # Try to generate envelope
    my $envelope_item = $profile->to_envelope_item();
    if ($envelope_item) {
        say "✅ Envelope generation worked!";
        say "   Envelope type: " . $envelope_item->{type};
        say "   Data present: " . (defined $envelope_item->{data} ? "YES" : "NO");
    } else {
        say "❌ Envelope generation failed";
    }
} else {
    say "❌ No samples collected";
}

# Test 2: Manual profiling with longer duration
say "\n🔬 Testing longer manual profiling session";
say "-" x 40;

my $manual_profile = Sentry::SDK->start_profiler({
    name => 'debug-manual-profiling'
});

say "Started manual profiling session";

# Do more intensive work for longer
for my $iteration (1..5) {
    say "  Iteration $iteration/5";
    
    # CPU intensive work
    for my $i (1..2000) {
        my $result = fibonacci($i % 20);
    }
    
    # Small delay to allow sampling
    usleep(10000);  # 10ms
}

say "Stopping manual profiling...";
my $stopped = Sentry::SDK->stop_profiler();

if ($stopped) {
    my $manual_stats = $stopped->get_stats();
    say "Manual profiling statistics:";
    say "  - Sample count: " . $manual_stats->{sample_count};
    say "  - Unique frames: " . $manual_stats->{unique_frames};
    say "  - Duration: " . sprintf("%.3fs", $manual_stats->{duration} || 0);
    
    if ($manual_stats->{sample_count} > 0) {
        say "✅ Manual profiling collected samples!";
    } else {
        say "❌ Manual profiling collected no samples";
    }
} else {
    say "❌ Failed to stop manual profiling";
}

# Test 3: Check signal handling
say "\n🔬 Testing signal handling";
say "-" x 25;

my $signal_test_profile = Sentry::Profiling::Profile->new();
my $signal_sampler = Sentry::Profiling::StackSampler->new(interval_us => 5000);

say "Testing SIGALRM availability...";

# Check if we can set up SIGALRM
eval {
    local $SIG{ALRM} = sub { 
        say "  ✅ SIGALRM received";
    };
    alarm(1);
    sleep(2);  # Should trigger the alarm
    alarm(0);  # Cancel any remaining alarm
};

if ($@) {
    say "❌ Signal handling error: $@";
} else {
    say "✅ Signal handling appears to work";
}

say "\n🎯 Debug Summary";
say "=" x 20;

my $final_profiler = Sentry::SDK->get_profiler();
if ($final_profiler) {
    say "✅ Profiler available from SDK";
    say "   Profiler class: " . ref($final_profiler);
    
    if ($final_profiler->can('config')) {
        my $config = $final_profiler->config;
        say "   Config available: YES";
        say "   Sampling interval: " . $config->sampling_interval_us . "µs";
        say "   Enable profiling: " . ($config->enable_profiling ? "YES" : "NO");
    }
} else {
    say "❌ No profiler available from SDK";
}

sub fibonacci {
    my ($n) = @_;
    return $n if $n <= 1;
    return fibonacci($n - 1) + fibonacci($n - 2);
}

__END__