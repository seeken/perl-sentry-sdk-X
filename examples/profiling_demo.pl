#!/usr/bin/env perl

use strict;
use warnings;
use feature 'say';

use lib '../lib';
use Sentry::SDK;

# Initialize SDK with profiling enabled
Sentry::SDK->init({
    dsn => $ENV{SENTRY_DSN} || 'https://test@sentry.io/1',
    enable_profiling => 1,
    profiles_sample_rate => 1.0,      # Profile 100% for demo
    profile_lifecycle => 'manual',    # Manual control
    sampling_interval_us => 5000,     # 5ms sampling for more detail
});

say "🎯 Sentry Profiling Demo";
say "=" x 40;

# Demo 1: Manual profiling
say "\n1. 📊 Manual Profiling";
say "-" x 20;

my $profile = Sentry::SDK->start_profiler({ name => 'expensive-computation' });
say "✅ Started profiler: expensive-computation";

# Simulate expensive computation
say "🔄 Running expensive computation...";
expensive_computation(100);

my $stopped_profile = Sentry::SDK->stop_profiler();
say "✅ Stopped profiler - profile sent to Sentry";

if ($stopped_profile) {
    my $stats = $stopped_profile->get_stats();
    say "📈 Profile stats:";
    say "   - Samples: $stats->{sample_count}";
    say "   - Unique frames: $stats->{unique_frames}";
    say "   - Unique stacks: $stats->{unique_stacks}";
    say "   - Duration: " . sprintf("%.3fs", $stats->{duration} // 0);
}

# Demo 2: Profiling code blocks
say "\n2. 🎭 Code Block Profiling";
say "-" x 20;

my $result = Sentry::SDK->profile('data-processing', sub {
    say "🔄 Processing data with profiling...";
    return process_data_with_recursion(5);
});

say "✅ Processed result: $result - profile sent to Sentry";

# Demo 3: Transaction-based profiling  
say "\n3. 🔗 Transaction-Based Profiling";
say "-" x 20;

# Switch to transaction-based profiling
Sentry::SDK->get_profiler->profile_lifecycle('trace');

my $transaction = Sentry::SDK->start_transaction({
    name => 'background-job',
    op => 'task',
});

say "✅ Started transaction - profiling automatically enabled" if $transaction->sampled;

# Do work within transaction
simulate_background_job();

$transaction->finish();
say "✅ Finished transaction - profile automatically sent";

say "\n🎉 Demo complete! Check your Sentry project for profiling data.";
say "Look for the 'Profiling' tab to see flame graphs and performance insights.";

# Helper functions
sub expensive_computation ($iterations) {
    my $result = 0;
    for my $i (1..$iterations) {
        $result += fibonacci($i % 15);
        usleep(1000) if $i % 10 == 0;  # Simulate I/O
    }
    return $result;
}

sub fibonacci ($n) {
    return $n if $n <= 1;
    return fibonacci($n - 1) + fibonacci($n - 2);
}

sub process_data_with_recursion ($depth) {
    return 1 if $depth <= 0;
    usleep(2000);  # Simulate processing
    return process_data_with_recursion($depth - 1) + $depth;
}

sub simulate_background_job {
    say "  🔄 Phase 1: Data validation";
    expensive_computation(50);
    
    say "  🔄 Phase 2: Data transformation";  
    process_data_with_recursion(3);
    
    say "  🔄 Phase 3: Result generation";
    expensive_computation(30);
}

sub usleep ($microseconds) {
    select(undef, undef, undef, $microseconds / 1_000_000);
}