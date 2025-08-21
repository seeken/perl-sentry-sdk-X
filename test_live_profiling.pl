#!/usr/bin/env perl

use strict;
use warnings;
use feature 'say';

use lib 'lib';
use Sentry::SDK;

my $dsn = 'https://bc1b329862866abb9c8f70c5dac940aa@sentry.cgtmigration.com/9';

say "🧪 Live Profiling Test";
say "DSN: $dsn";
say "=" x 50;

# Initialize SDK with profiling enabled
Sentry::SDK->init({
    dsn => $dsn,
    
    # Enable tracing and profiling
    traces_sample_rate => 1.0,      # 100% of transactions
    profiles_sample_rate => 1.0,    # Profile all transactions
    enable_profiling => 1,
    
    # Use frequent sampling for testing
    sampling_interval_us => 5000,   # 5ms
    adaptive_sampling => 0,         # Disable for consistent testing
    
    debug => 1,                     # Enable debug output
});

say "✅ SDK initialized with profiling enabled";

# Get profiler to verify it's available
my $profiler = Sentry::SDK->get_profiler();
if (!$profiler) {
    die "❌ Profiler not available - check SDK initialization";
}

say "✅ Profiler is available";

# Test 1: Manual profiling
say "\n🔬 Test 1: Manual Profiling";
say "-" x 30;

my $profile = Sentry::SDK->start_profiler({
    name => 'live-test-manual-profiling'
});

say "   Started manual profiling...";

# Generate some stack activity
cpu_intensive_work();
memory_intensive_work();

my $stopped_profile = Sentry::SDK->stop_profiler();

if ($stopped_profile) {
    my $stats = $stopped_profile->get_stats();
    say "   ✅ Manual profiling completed";
    say "      - Samples: " . $stats->{sample_count};
    say "      - Unique frames: " . $stats->{unique_frames};
    say "      - Duration: " . sprintf("%.3fs", $stats->{duration} || 0);
} else {
    say "   ❌ Manual profiling failed";
}

# Test 2: Transaction-based profiling
say "\n🔬 Test 2: Transaction Profiling";
say "-" x 35;

my $transaction = Sentry::SDK->start_transaction({
    name => 'live-test-transaction',
    op => 'test',
});

say "   Started transaction with automatic profiling...";

# Add some context
Sentry::SDK->configure_scope(sub {
    my $scope = shift;
    $scope->set_tag('test_type', 'live_profiling');
    $scope->set_context('test_info', {
        perl_version => $^V,
        platform => $^O,
        timestamp => time(),
    });
});

# Generate work to profile
recursive_work(10);
string_processing();
array_operations();

say "   Finishing transaction...";
$transaction->finish();

say "   ✅ Transaction completed and profile sent";

# Test 3: Block profiling
say "\n🔬 Test 3: Block Profiling";
say "-" x 25;

my $result = Sentry::SDK->profile(sub {
    say "   Running profiled computation...";
    return fibonacci_computation();
});

say "   ✅ Block profiling result: $result";

# Test 4: Send a test error to verify connection
say "\n🔬 Test 4: Connection Verification";
say "-" x 35;

eval {
    die "Live profiling test error - connection verification";
};

if ($@) {
    Sentry::SDK->capture_exception($@);
    say "   ✅ Test error sent to verify Sentry connection";
}

say "\n🎉 Live profiling tests complete!";
say "";
say "Check your Sentry project for:";
say "  1. Profiling data from manual profiling session";
say "  2. Transaction profile with flame graph";
say "  3. Block profiling data";
say "  4. Test error event (connection verification)";
say "";
say "Expected in Sentry dashboard:";
say "  • Performance > Profiles section";
say "  • Flame graphs showing function call hierarchies";
say "  • Profile correlation with transactions";
say "  • Error event in Issues section";

# Work simulation functions

sub cpu_intensive_work {
    my $result = 0;
    for my $i (1..2000) {
        $result += fibonacci($i % 15);
    }
    return $result;
}

sub memory_intensive_work {
    my @data = map { { id => $_, data => "x" x ($_ % 100) } } 1..1000;
    return scalar @data;
}

sub recursive_work {
    my $depth = shift;
    return $depth if $depth <= 1;
    return recursive_work($depth - 1) + recursive_work($depth - 2);
}

sub string_processing {
    my @strings = map { "string_$_" x ($_ % 10 + 1) } 1..500;
    my $result = join(":", @strings);
    return length($result);
}

sub array_operations {
    my @data = 1..1000;
    @data = sort { $b <=> $a } @data;
    @data = grep { $_ % 2 == 0 } @data;
    return scalar @data;
}

sub fibonacci_computation {
    my $result = 0;
    for my $i (1..20) {
        $result += fibonacci($i);
    }
    return $result;
}

sub fibonacci {
    my ($n) = @_;
    return $n if $n <= 1;
    return fibonacci($n - 1) + fibonacci($n - 2);
}

__END__

=head1 NAME

test_live_profiling.pl - Live test of Sentry profiling with real DSN

=head1 DESCRIPTION

This script performs comprehensive live testing of the Sentry profiling
functionality using a real Sentry DSN. It tests:

1. Manual profiling start/stop
2. Transaction-based automatic profiling  
3. Block profiling with code blocks
4. Connection verification with error capture

The script generates various types of computational work to create
meaningful profiling data that will appear in the Sentry dashboard.

=head1 USAGE

    perl test_live_profiling.pl

Make sure to check your Sentry project dashboard after running to verify
that profiling data was received and processed correctly.

=cut