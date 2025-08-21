#!/usr/bin/env perl

use strict;
use warnings;
use feature 'say';

use lib '../lib';
use Sentry::SDK;

# Initialize SDK with advanced profiling configuration
Sentry::SDK->init({
    dsn => $ENV{SENTRY_DSN} || 'https://test@sentry.io/1',
    
    # Basic profiling settings
    enable_profiling => 1,
    profiles_sample_rate => 1.0,      # Profile 100% for demo
    profile_lifecycle => 'trace',     # Auto-profile with transactions
    sampling_interval_us => 5000,     # 5ms sampling
    
    # Advanced profiling settings
    adaptive_sampling => 1,           # Adjust sampling based on load
    cpu_threshold_percent => 70,      # Reduce sampling if CPU > 70%
    memory_threshold_mb => 50,        # Reduce sampling if memory > 50MB
    max_stack_depth => 50,            # Limit stack depth
    max_frames_per_sample => 100,     # Limit frames per sample
    
    # Package filtering
    ignore_packages => [
        'Test::', 'DBI', 'JSON::'     # Ignore these packages
    ],
});

say "🎯 Advanced Sentry Profiling Demo";
say "=" x 45;

my $profiler = Sentry::SDK->get_profiler();
if (!$profiler) {
    die "❌ Profiler not available";
}

# Display configuration
say "\n📋 Profiling Configuration:";
say "-" x 25;
my $config = $profiler->config;
say "  Enable Profiling: " . ($config->enable_profiling ? "✅" : "❌");
say "  Sample Rate: " . ($config->profiles_sample_rate * 100) . "%";
say "  Adaptive Sampling: " . ($config->adaptive_sampling ? "✅" : "❌");
say "  Sampling Interval: " . ($config->sampling_interval_us / 1000) . "ms";
say "  Max Stack Depth: " . $config->max_stack_depth;
say "  Profile Lifecycle: " . $config->profile_lifecycle;

# Demo 1: System monitoring
say "\n1. 🖥️  System Monitoring";
say "-" x 25;

require Sentry::Profiling::Utils;
my $utils = Sentry::Profiling::Utils->new();

my $cpu = $utils->get_cpu_usage();
my $memory = $utils->get_memory_usage_mb();

say "  Current CPU Usage: ${cpu}%";
say "  Current Memory: ${memory}MB";

# Show adaptive sampling in action
my $effective_interval = $config->get_effective_sampling_interval($cpu, $memory);
say "  Effective Sampling Interval: " . ($effective_interval / 1000) . "ms";

if ($effective_interval != $config->sampling_interval_us) {
    say "  ⚡ Adaptive sampling adjusted interval based on system load";
}

# Demo 2: Transaction-based profiling with performance monitoring
say "\n2. 📊 Transaction Profiling";
say "-" x 25;

my $transaction = Sentry::SDK->start_transaction({
    name => 'advanced-profiling-demo',
    op => 'demo',
});

say "  ✅ Started transaction with automatic profiling";

# Simulate different types of work
simulate_cpu_intensive_work();
simulate_memory_intensive_work(); 
simulate_io_operations();

my $profile_before_finish = $profiler->get_active_profile();
if ($profile_before_finish) {
    my $stats = $profile_before_finish->get_stats();
    say "  📈 Profile stats so far:";
    say "     - Samples: " . $stats->{sample_count};
    say "     - Unique frames: " . $stats->{unique_frames};
    say "     - Duration: " . sprintf("%.3fs", $stats->{duration} || 0);
}

$transaction->finish();
say "  ✅ Transaction finished, profile sent to Sentry";

# Demo 3: Manual profiling with filtering
say "\n3. 🎛️  Manual Profiling with Filtering";
say "-" x 35;

my $profile = Sentry::SDK->start_profiler({ 
    name => 'filtered-computation' 
});

say "  🔄 Running computation with package filtering...";

# This should be filtered out (Test:: packages ignored)
test_package_filtering();

# This should be included (application code)
application_specific_work();

# This should be filtered (DBI ignored)
database_simulation();

my $stopped_profile = Sentry::SDK->stop_profiler();

if ($stopped_profile) {
    my $stats = $stopped_profile->get_stats();
    my $metadata = $utils->create_profile_metadata($stopped_profile, $config);
    
    say "  📊 Final profile statistics:";
    say "     - Total samples: " . $stats->{sample_count};
    say "     - Unique frames: " . $stats->{unique_frames};
    say "     - Unique stacks: " . $stats->{unique_stacks};
    say "     - Duration: " . sprintf("%.3fs", $stats->{duration} || 0);
    say "     - Estimated overhead: " . sprintf("%.2f%%", $metadata->{estimated_overhead_percent});
}

# Demo 4: Performance measurement utility
say "\n4. ⏱️  Performance Measurement";
say "-" x 30;

my ($result, $duration) = $utils->time_execution(sub {
    expensive_fibonacci(25);
});

say "  🔢 Fibonacci result: $result";
say "  ⏰ Execution time: " . sprintf("%.4fs", $duration);
say "  📈 Performance measured with high precision";

say "\n🎉 Advanced profiling demo complete!";
say "Check your Sentry project for detailed profiling data with:";
say "  • Flame graphs showing call hierarchies";  
say "  • Performance bottleneck identification";
say "  • Frame-level execution time analysis";
say "  • Filtered views excluding system packages";

# Helper functions for different types of work

sub simulate_cpu_intensive_work {
    say "    🔄 CPU-intensive computation...";
    my $result = 0;
    for my $i (1..1000) {
        $result += fibonacci($i % 15);
    }
    return $result;
}

sub simulate_memory_intensive_work {
    say "    🧠 Memory-intensive operations...";
    my @data;
    for my $i (1..1000) {
        push @data, { id => $i, data => "x" x ($i % 100) };
    }
    return scalar @data;
}

sub simulate_io_operations {
    say "    💾 I/O simulation...";
    for my $i (1..10) {
        select(undef, undef, undef, 0.01);  # Simulate I/O delay
    }
}

sub test_package_filtering {
    # This simulates Test:: package that should be filtered
    package Test::Filtered;
    sub filtered_function {
        my $x = 0;
        $x++ for 1..100;
        return $x;
    }
    return filtered_function();
}

sub application_specific_work {
    package MyApp::Core;
    sub important_business_logic {
        my $result = 0;
        for my $i (1..50) {
            $result += $i * $i;
        }
        return $result;
    }
    return important_business_logic();
}

sub database_simulation {
    package DBI::Simulation;
    sub execute_query {
        select(undef, undef, undef, 0.005);  # Simulate query time
        return "query_result";
    }
    return execute_query();
}

sub fibonacci {
    my ($n) = @_;
    return $n if $n <= 1;
    return fibonacci($n - 1) + fibonacci($n - 2);
}

sub expensive_fibonacci {
    my ($n) = @_;
    return fibonacci($n);
}