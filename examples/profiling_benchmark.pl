#!/usr/bin/env perl

use strict;
use warnings;
use feature 'say';
use Time::HiRes qw(time sleep);

# Optional module for advanced statistics
my $HAS_STATISTICS;
BEGIN {
    eval { require Statistics::Descriptive; 1 };
    $HAS_STATISTICS = !$@;
    unless ($HAS_STATISTICS) {
        warn "Statistics::Descriptive not available - using basic statistics\n";
    }
}

use lib '../lib';
use Sentry::SDK;
use Sentry::Profiling::Utils;

say "⚡ Sentry Profiling Performance Benchmark";
say "=" x 45;

# Test configurations
my @configs = (
    {
        name => 'Disabled',
        settings => { enable_profiling => 0 },
    },
    {
        name => 'Basic (10ms)',
        settings => { 
            enable_profiling => 1,
            profiles_sample_rate => 1.0,
            sampling_interval_us => 10000,
            adaptive_sampling => 0,
        },
    },
    {
        name => 'High Frequency (1ms)',
        settings => { 
            enable_profiling => 1,
            profiles_sample_rate => 1.0,
            sampling_interval_us => 1000,
            adaptive_sampling => 0,
        },
    },
    {
        name => 'Adaptive',
        settings => { 
            enable_profiling => 1,
            profiles_sample_rate => 1.0,
            sampling_interval_us => 5000,
            adaptive_sampling => 1,
            cpu_threshold_percent => 50,
        },
    },
    {
        name => 'Production',
        settings => { 
            enable_profiling => 1,
            profiles_sample_rate => 0.1,  # 10% sampling
            sampling_interval_us => 10000,
            adaptive_sampling => 1,
            max_stack_depth => 20,
        },
    },
);

# Benchmark workloads
my @workloads = (
    {
        name => 'CPU Intensive',
        description => 'Pure computation',
        work => \&cpu_intensive_work,
        iterations => 5,
    },
    {
        name => 'Memory Allocation',
        description => 'Memory-heavy operations',
        work => \&memory_intensive_work,
        iterations => 3,
    },
    {
        name => 'Mixed Workload',
        description => 'CPU + Memory + I/O',
        work => \&mixed_workload,
        iterations => 3,
    },
    {
        name => 'Deep Recursion',
        description => 'Deep call stack',
        work => \&recursive_work,
        iterations => 5,
    },
);

my $utils = Sentry::Profiling::Utils->new();
my %results;

say "\n🏁 Starting performance benchmarks...";
say "Each test runs multiple iterations to ensure statistical significance\n";

for my $config (@configs) {
    say "📊 Testing configuration: $config->{name}";
    say "   " . format_config($config->{settings});
    
    # Initialize SDK with current configuration
    Sentry::SDK->init({
        dsn => $ENV{SENTRY_DSN} || 'https://test@sentry.io/1',
        %{$config->{settings}},
    });
    
    for my $workload (@workloads) {
        say "     🔄 $workload->{name}: $workload->{description}";
        
        my @times;
        my @memory_usage;
        my @cpu_usage;
        
        for my $iteration (1..$workload->{iterations}) {
            # Measure system resources before
            my $cpu_before = $utils->get_cpu_usage();
            my $memory_before = $utils->get_memory_usage_mb();
            
            # Run the workload with timing
            my $start_time = time();
            my $result = $workload->{work}->();
            my $end_time = time();
            
            my $duration = $end_time - $start_time;
            push @times, $duration;
            
            # Measure system resources after
            my $cpu_after = $utils->get_cpu_usage();
            my $memory_after = $utils->get_memory_usage_mb();
            
            push @cpu_usage, $cpu_after - $cpu_before;
            push @memory_usage, $memory_after - $memory_before;
            
            # Small delay between iterations
            sleep(0.1);
        }
        
        # Calculate statistics
        my $stat;
        if ($HAS_STATISTICS) {
            $stat = Statistics::Descriptive::Full->new();
            $stat->add_data(@times);
        } else {
            # Basic statistics fallback
            $stat = {
                mean => average(@times),
                standard_deviation => 0,
                min => min(@times),
                max => max(@times),
            };
        }
        
        $results{$config->{name}}{$workload->{name}} = {
            mean => $HAS_STATISTICS ? $stat->mean() : $stat->{mean},
            stddev => $HAS_STATISTICS ? $stat->standard_deviation() : $stat->{standard_deviation},
            min => $HAS_STATISTICS ? $stat->min() : $stat->{min},
            max => $HAS_STATISTICS ? $stat->max() : $stat->{max},
            samples => scalar(@times),
            cpu_delta => average(@cpu_usage),
            memory_delta => average(@memory_usage),
        };
        
        my $mean = $HAS_STATISTICS ? $stat->mean() : $stat->{mean};
        my $stddev = $HAS_STATISTICS ? $stat->standard_deviation() : $stat->{standard_deviation};
        my $min_time = $HAS_STATISTICS ? $stat->min() : $stat->{min};
        my $max_time = $HAS_STATISTICS ? $stat->max() : $stat->{max};
        
        printf("        ⏱️  %.4fs ± %.4fs (min: %.4fs, max: %.4fs)\n", 
               $mean, $stddev || 0, $min_time, $max_time);
    }
    say "";
}

# Generate performance report
say "\n📈 Performance Impact Analysis";
say "=" x 35;

my $baseline = $results{'Disabled'};

say sprintf("%-20s %-18s %10s %12s %8s", 
           "Configuration", "Workload", "Overhead", "vs Baseline", "Impact");
say "-" x 75;

for my $config_name (keys %results) {
    next if $config_name eq 'Disabled';
    
    my $config_results = $results{$config_name};
    
    for my $workload_name (keys %{$config_results}) {
        my $current = $config_results->{$workload_name};
        my $baseline_time = $baseline->{$workload_name}{mean};
        
        my $overhead = $current->{mean} - $baseline_time;
        my $overhead_percent = ($overhead / $baseline_time) * 100;
        
        my $impact = $overhead_percent < 5 ? "Low" : 
                    $overhead_percent < 15 ? "Medium" : "High";
        
        printf("%-20s %-18s %8.1fms %10.1f%% %8s\n",
               $config_name, $workload_name, 
               $overhead * 1000, $overhead_percent, $impact);
    }
}

# Memory usage analysis
say "\n💾 Memory Impact Analysis";
say "-" x 25;

for my $config_name (keys %results) {
    next if $config_name eq 'Disabled';
    
    say "Configuration: $config_name";
    my $config_results = $results{$config_name};
    
    for my $workload_name (keys %{$config_results}) {
        my $memory_delta = $config_results->{$workload_name}{memory_delta};
        printf("  %-18s: %+.1f MB\n", $workload_name, $memory_delta);
    }
    say "";
}

# Generate recommendations
say "\n💡 Performance Recommendations";
say "=" x 32;

my @recommendations;

# Check for high overhead configurations
for my $config_name (keys %results) {
    next if $config_name eq 'Disabled';
    
    my $total_overhead = 0;
    my $workload_count = 0;
    
    for my $workload_name (keys %{$results{$config_name}}) {
        my $current = $results{$config_name}{$workload_name}{mean};
        my $baseline_time = $baseline->{$workload_name}{mean};
        my $overhead_percent = (($current - $baseline_time) / $baseline_time) * 100;
        
        $total_overhead += $overhead_percent;
        $workload_count++;
    }
    
    my $avg_overhead = $total_overhead / $workload_count;
    
    if ($avg_overhead < 5) {
        push @recommendations, "✅ $config_name: Excellent performance, minimal overhead (<5%)";
    } elsif ($avg_overhead < 15) {
        push @recommendations, "⚠️  $config_name: Acceptable performance, moderate overhead (<15%)";
    } else {
        push @recommendations, "❌ $config_name: High overhead (>15%), consider reducing sampling frequency";
    }
}

# Print recommendations
for my $rec (@recommendations) {
    say $rec;
}

say "\n🎯 Optimal Configuration Suggestions:";
say "   • For development: Use 'Basic (10ms)' for good balance";
say "   • For staging: Use 'Adaptive' to handle variable loads";
say "   • For production: Use 'Production' with low sample rate";
say "   • For debugging: Use 'High Frequency (1ms)' temporarily";

say "\n📊 Complete benchmark results saved to benchmark_results.txt";

# Save detailed results to file
save_results_to_file(\%results, $baseline);

# Workload implementations
sub cpu_intensive_work {
    my $result = 0;
    for my $i (1..5000) {
        $result += fibonacci($i % 20);
    }
    return $result;
}

sub memory_intensive_work {
    my @data;
    for my $i (1..2000) {
        push @data, { 
            id => $i, 
            data => "x" x ($i % 200),
            metadata => { created => time(), index => $i }
        };
    }
    return scalar @data;
}

sub mixed_workload {
    # CPU work
    my $cpu_result = 0;
    for my $i (1..1000) {
        $cpu_result += $i * $i;
    }
    
    # Memory work
    my @data = map { { id => $_, value => $_ * 2 } } 1..1000;
    
    # I/O simulation
    for my $i (1..10) {
        select(undef, undef, undef, 0.001);
    }
    
    return $cpu_result + scalar(@data);
}

sub recursive_work {
    return deep_recursion(15);
}

sub deep_recursion {
    my ($depth) = @_;
    return $depth if $depth <= 1;
    return deep_recursion($depth - 1) + deep_recursion($depth - 2);
}

sub fibonacci {
    my ($n) = @_;
    return $n if $n <= 1;
    return fibonacci($n - 1) + fibonacci($n - 2);
}

sub format_config {
    my ($settings) = @_;
    my @parts;
    
    if ($settings->{enable_profiling}) {
        push @parts, "profiling: enabled";
        push @parts, "interval: " . ($settings->{sampling_interval_us} / 1000) . "ms";
        push @parts, "adaptive: " . ($settings->{adaptive_sampling} ? "yes" : "no");
        push @parts, "sample_rate: " . ($settings->{profiles_sample_rate} * 100) . "%";
    } else {
        push @parts, "profiling: disabled";
    }
    
    return join(", ", @parts);
}

sub average {
    my @values = @_;
    return 0 unless @values;
    my $sum = 0;
    $sum += $_ for @values;
    return $sum / @values;
}

sub min {
    my @values = @_;
    return 0 unless @values;
    my $min = $values[0];
    for my $val (@values) {
        $min = $val if $val < $min;
    }
    return $min;
}

sub max {
    my @values = @_;
    return 0 unless @values;
    my $max = $values[0];
    for my $val (@values) {
        $max = $val if $val > $max;
    }
    return $max;
}

sub save_results_to_file {
    my ($results, $baseline) = @_;
    
    open my $fh, '>', 'benchmark_results.txt' or return;
    
    print $fh "Sentry Profiling Performance Benchmark Results\n";
    print $fh "=" x 50, "\n";
    print $fh "Generated: " . scalar(localtime) . "\n\n";
    
    # Detailed results
    for my $config_name (sort keys %$results) {
        print $fh "Configuration: $config_name\n";
        print $fh "-" x 30, "\n";
        
        my $config_results = $results->{$config_name};
        
        for my $workload_name (sort keys %$config_results) {
            my $stats = $config_results->{$workload_name};
            
            print $fh sprintf("  %-18s: %.4fs ± %.4fs (%d samples)\n",
                            $workload_name, $stats->{mean}, 
                            $stats->{stddev} || 0, $stats->{samples});
            
            if ($config_name ne 'Disabled') {
                my $baseline_time = $baseline->{$workload_name}{mean};
                my $overhead = ($stats->{mean} - $baseline_time) / $baseline_time * 100;
                print $fh sprintf("                    Overhead: %.1f%%\n", $overhead);
            }
        }
        print $fh "\n";
    }
    
    close $fh;
}