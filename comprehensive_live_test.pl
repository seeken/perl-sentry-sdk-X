#!/usr/bin/env perl

use strict;
use warnings;
use feature 'say';
use Time::HiRes qw(sleep time);
use JSON qw(encode_json);

use lib 'lib';
use Sentry::SDK;

my $dsn = 'https://bc1b329862866abb9c8f70c5dac940aa@sentry.cgtmigration.com/9';

say "🚀 COMPREHENSIVE Live Profiling Test";
say "DSN: $dsn";
say "=" x 50;

# Initialize with settings that will definitely work
Sentry::SDK->init({
    dsn => $dsn,
    traces_sample_rate => 1.0,
    profiles_sample_rate => 1.0,
    enable_profiling => 1,
    sampling_interval_us => 2000,    # 2ms - frequent but not excessive
    adaptive_sampling => 0,          # Disabled for predictable testing
    debug => 1,
});

say "✅ SDK initialized with profiling enabled";

# Test 1: Long-running manual profiling
say "\n🔬 Test 1: Long-running Manual Profiling";
say "-" x 40;

my $profile = Sentry::SDK->start_profiler({
    name => 'comprehensive-manual-test'
});

if (!$profile) {
    die "❌ Failed to start profiler";
}

say "✅ Manual profiling started";

# Generate significant work that will definitely be sampled
say "   Running CPU-intensive work for profiling...";

for my $batch (1..5) {
    say "     Batch $batch/5";
    
    # Each batch does different types of work
    cpu_work();
    memory_work(); 
    string_work();
    recursion_work();
    
    # Ensure some time passes for sampling
    sleep(0.02);  # 20ms
}

say "   Stopping manual profiler...";
my $stopped_profile = Sentry::SDK->stop_profiler();

if ($stopped_profile) {
    my $stats = $stopped_profile->get_stats();
    say "   📊 Manual Profile Results:";
    say "      - Duration: " . sprintf("%.3fs", $stats->{duration} || 0);
    say "      - Samples: " . $stats->{sample_count};
    say "      - Unique frames: " . $stats->{unique_frames};
    say "      - Unique stacks: " . $stats->{unique_stacks};
    
    if ($stats->{sample_count} > 0) {
        say "   ✅ Manual profiling collected data successfully!";
        
        # Check envelope generation
        my $envelope_item = $stopped_profile->to_envelope_item();
        if ($envelope_item) {
            say "   ✅ Envelope generated successfully";
            say "      - Type: " . $envelope_item->{type};
            say "      - Has profile data: " . (defined $envelope_item->{profile} ? "YES" : "NO");
            
            if ($envelope_item->{profile}) {
                my $profile_data = $envelope_item->{profile};
                my $sample_count = scalar(@{$profile_data->{samples} || []});
                my $frame_count = scalar(@{$profile_data->{frames} || []});
                my $stack_count = scalar(@{$profile_data->{stacks} || []});
                
                say "      - Samples in envelope: $sample_count";
                say "      - Frames in envelope: $frame_count";
                say "      - Stacks in envelope: $stack_count";
                say "      - Duration (ns): " . ($profile_data->{duration_ns} || 0);
            }
        } else {
            say "   ❌ Failed to generate envelope";
        }
    } else {
        say "   ❌ No samples collected in manual profiling";
    }
} else {
    say "   ❌ Failed to stop manual profiler";
}

# Test 2: Transaction-based profiling with longer duration
say "\n🔬 Test 2: Transaction-based Profiling";
say "-" x 38;

my $transaction = Sentry::SDK->start_transaction({
    name => 'comprehensive-transaction-test',
    op => 'test.profiling',
});

if (!$transaction) {
    die "❌ Failed to start transaction";
}

say "✅ Transaction started with automatic profiling";

# Add context for better debugging
Sentry::SDK->configure_scope(sub {
    my $scope = shift;
    $scope->set_tag('test_type', 'comprehensive_profiling');
    $scope->set_tag('test_version', '1.0');
    $scope->set_context('test_environment', {
        perl_version => "$^V",
        platform => "$^O",
        pid => "$$",
        start_time => time(),
    });
});

# Do substantial work that will generate profile data
say "   Executing substantial workload...";

for my $iteration (1..10) {
    say "     Iteration $iteration/10";
    
    # Mix of different computation types
    mathematical_computation();
    text_processing();
    data_structures();
    nested_function_calls();
    
    # Sleep to ensure sampling opportunities
    sleep(0.01);  # 10ms between iterations
}

say "   Finishing transaction...";

# Finish transaction - this should send profile data
$transaction->finish();

say "   ✅ Transaction completed - profile data sent to Sentry";

# Test 3: Send a test error for verification
say "\n🔬 Test 3: Connection Verification";
say "-" x 33;

eval {
    die "Comprehensive profiling test - connection verification";
};

if ($@) {
    Sentry::SDK->capture_exception($@);
    say "   ✅ Test error sent for connection verification";
}

# Summary
say "\n🎯 Test Summary";
say "=" x 20;

my $current_profiler = Sentry::SDK->get_profiler();
if ($current_profiler) {
    say "✅ Profiler still available";
    say "   Currently active: " . ($current_profiler->is_profiling_active() ? "YES" : "NO");
    
    if ($current_profiler->can('config')) {
        my $config = $current_profiler->config;
        say "   Configuration:";
        say "     - Enabled: " . ($config->enable_profiling ? "YES" : "NO");
        say "     - Sample rate: " . ($config->profiles_sample_rate * 100) . "%";
        say "     - Interval: " . ($config->sampling_interval_us / 1000) . "ms";
    }
}

say "\n📋 What to Check in Sentry:";
say "-" x 30;
say "1. Performance > Profiles section should show:";
say "   • Profile from manual profiling session";
say "   • Profile from transaction 'comprehensive-transaction-test'";
say "   • Flame graphs with function call hierarchies";
say "   • Stack traces from CPU-intensive functions";
say "";
say "2. Issues section should show:";
say "   • Test error for connection verification";
say "";
say "3. Expected profile data:";
say "   • cpu_work, memory_work, string_work functions";
say "   • mathematical_computation, text_processing functions";
say "   • Recursive fibonacci calls";
say "   • Nested function call patterns";

say "\n🎉 Comprehensive live test completed!";
say "Check your Sentry project dashboard for profiling data.";

# Work functions to generate interesting profile data

sub cpu_work {
    my $result = 0;
    for my $i (1..1000) {
        $result += fibonacci($i % 20);
    }
    return $result;
}

sub memory_work {
    my @data = map { 
        { 
            id => $_, 
            value => $_ * 2, 
            text => "item_$_" x ($_ % 10 + 1) 
        } 
    } 1..500;
    
    # Sort and filter
    @data = sort { $a->{value} <=> $b->{value} } @data;
    @data = grep { $_->{value} % 2 == 0 } @data;
    
    return scalar @data;
}

sub string_work {
    my @strings = map { "string_$_" } 1..1000;
    my $combined = join(",", @strings);
    my @split = split(/,/, $combined);
    return length($combined) + scalar(@split);
}

sub recursion_work {
    return deep_recursion(12);
}

sub deep_recursion {
    my ($depth) = @_;
    return $depth if $depth <= 1;
    return deep_recursion($depth - 1) + deep_recursion($depth - 2);
}

sub mathematical_computation {
    my $sum = 0;
    for my $i (1..1000) {
        $sum += sqrt($i) * log($i + 1);
    }
    return $sum;
}

sub text_processing {
    my $text = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. " x 100;
    $text =~ s/[aeiou]/X/g;
    my @words = split(/\s+/, $text);
    return scalar(@words);
}

sub data_structures {
    my %hash;
    for my $i (1..500) {
        $hash{"key_$i"} = {
            value => $i,
            squared => $i * $i,
            factors => [grep { $i % $_ == 0 } 1..$i],
        };
    }
    return scalar(keys %hash);
}

sub nested_function_calls {
    level1();
}

sub level1 {
    level2();
}

sub level2 {
    level3();
}

sub level3 {
    level4();
}

sub level4 {
    my $result = 0;
    for my $i (1..200) {
        $result += $i * $i;
    }
    return $result;
}

sub fibonacci {
    my ($n) = @_;
    return $n if $n <= 1;
    return fibonacci($n - 1) + fibonacci($n - 2);
}

__END__