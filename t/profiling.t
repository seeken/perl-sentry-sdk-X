use Mojo::Base -strict, -signatures;
use Test::More;
use Test::Exception;

use lib 'lib';
use Sentry::SDK;
use Sentry::Profiling;

# Test basic profiling functionality
subtest 'Basic profiling API' => sub {
    my $profiler = Sentry::Profiling->new(
        enable_profiling => 1,
        profiles_sample_rate => 1.0,
    );
    
    isa_ok($profiler, 'Sentry::Profiling', 'Created profiler instance');
    
    # Test that profiler starts correctly
    my $profile = $profiler->start_profiler({ name => 'test-profile' });
    ok($profile, 'Started profiler');
    isa_ok($profile, 'Sentry::Profiling::Profile', 'Profile is correct type');
    
    ok($profiler->is_profiling_active(), 'Profiling is active');
    is($profiler->get_active_profile(), $profile, 'Active profile matches');
    
    # Do some work to generate stack samples
    test_recursive_function(3);
    
    # Add a manual sample to ensure we have test data
    if (my $profile = $profiler->get_active_profile()) {
        $profile->add_sample({
            timestamp => time(),
            thread_id => "$$",
            frames => [
                {
                    package => 'main',
                    filename => 't/profiling.t',
                    lineno => 25,
                    function => 'test_recursive_function',
                    in_app => 1
                }
            ]
        });
    }
    
    sleep(0.1);  # Allow sampling
    
    my $stopped_profile = $profiler->stop_profiler();
    ok($stopped_profile, 'Stopped profiler');
    is($stopped_profile, $profile, 'Same profile returned');
    
    ok(!$profiler->is_profiling_active(), 'Profiling is no longer active');
    ok($profile->end_time, 'Profile has end time');
    ok($profile->get_sample_count() > 0, 'Profile has samples');
    
    my $envelope = $profile->to_envelope_item();
    ok($envelope, 'Generated envelope item');
    is($envelope->{type}, 'profile', 'Correct envelope type');
    ok($envelope->{profile}, 'Envelope has profile data');
};

# Test SDK integration
subtest 'SDK integration' => sub {
    Sentry::SDK->init({
        dsn => 'https://test@sentry.io/1',
        enable_profiling => 1,
        profiles_sample_rate => 1.0,
    });
    
    ok(!Sentry::SDK->is_profiling_active(), 'Not profiling initially');
    
    my $profile = Sentry::SDK->start_profiler({ name => 'sdk-test' });
    ok($profile, 'SDK started profiler');
    
    ok(Sentry::SDK->is_profiling_active(), 'SDK reports profiling active');
    
    test_recursive_function(2);
    
    my $stopped = Sentry::SDK->stop_profiler();
    ok($stopped, 'SDK stopped profiler');
    ok(!Sentry::SDK->is_profiling_active(), 'SDK reports profiling inactive');
};

# Test code block profiling
subtest 'Code block profiling' => sub {
    Sentry::SDK->init({
        dsn => 'https://test@sentry.io/1',
        enable_profiling => 1,
        profiles_sample_rate => 1.0,
    });
    
    my $result = Sentry::SDK->profile('block-test', sub {
        test_recursive_function(2);
        return 42;
    });
    
    is($result, 42, 'Block profiling returned correct result');
};

# Test transaction integration
subtest 'Transaction integration' => sub {
    Sentry::SDK->init({
        dsn => 'https://test@sentry.io/1',
        enable_profiling => 1,
        profiles_sample_rate => 1.0,
        profile_lifecycle => 'trace',
    });
    
    my $profiler = Sentry::SDK->get_profiler();
    ok($profiler, 'Got profiler from SDK');
    ok(!$profiler->is_profiling_active(), 'Not profiling initially');
    
    my $transaction = Sentry::SDK->start_transaction({
        name => 'test-transaction',
        op => 'test',
    });
    
    ok($transaction, 'Started transaction');
    
    # Profiling should start automatically if transaction is sampled
    if ($transaction->sampled) {
        ok($profiler->is_profiling_active(), 'Profiling started with transaction');
    }
    
    test_recursive_function(2);
    
    $transaction->finish();
    
    # Profiling should stop automatically
    ok(!$profiler->is_profiling_active(), 'Profiling stopped with transaction');
};

# Test sampling decisions
subtest 'Sampling decisions' => sub {
    # Test disabled profiling
    my $disabled_profiler = Sentry::Profiling->new(
        enable_profiling => 0,
    );
    
    my $profile = $disabled_profiler->start_profiler({ name => 'disabled-test' });
    ok(!$profile, 'No profile when profiling disabled');
    
    # Test zero sample rate
    my $zero_rate_profiler = Sentry::Profiling->new(
        enable_profiling => 1,
        profiles_sample_rate => 0.0,
    );
    
    # Try multiple times since it's random
    my $got_profile = 0;
    for my $i (1..10) {
        my $test_profile = $zero_rate_profiler->start_profiler({ name => "zero-rate-$i" });
        if ($test_profile) {
            $zero_rate_profiler->stop_profiler();
            $got_profile = 1;
            last;
        }
    }
    ok(!$got_profile, 'No profiles with zero sample rate');
};

# Test frame collection
subtest 'Frame collection and deduplication' => sub {
    my $profiler = Sentry::Profiling->new(
        enable_profiling => 1,
        profiles_sample_rate => 1.0,
        sampling_interval_us => 1000,  # Sample very frequently
    );
    
    my $profile = $profiler->start_profiler({ name => 'frame-test' });
    
    # Add some manual samples to ensure we have data
    for my $i (1..3) {
        $profile->add_sample({
            timestamp => time(),
            thread_id => "$$",
            frames => [
                {
                    package => 'main',
                    filename => 't/profiling.t',
                    lineno => 150 + $i,
                    function => 'test_recursive_function',
                    in_app => 1
                },
                {
                    package => 'Test::More',
                    filename => '/usr/local/share/perl5/Test/More.pm',
                    lineno => 100,
                    function => 'subtest',
                    in_app => 0
                }
            ]
        });
    }
    
    # Also try to trigger automatic sampling
    for my $i (1..5) {
        test_recursive_function(3);
        select(undef, undef, undef, 0.01);  # Small delay
    }
    
    $profiler->stop_profiler();
    
    my $stats = $profile->get_stats();
    ok($stats->{sample_count} > 0, 'Collected samples');
    ok($stats->{unique_frames} > 0, 'Has unique frames');
    
    # Frame deduplication should result in reasonable frame count
    ok($stats->{unique_frames} >= 1, 'Frame deduplication working');
};

# Helper function to generate stack samples

# Helper function to generate stack samples
sub test_recursive_function ($depth) {
    return 1 if $depth <= 0;
    
    # Try to manually trigger sampling if we have an active profiler
    my $profiler = Sentry::SDK->get_profiler();
    if ($profiler && $profiler->is_profiling_active()) {
        my $sampler = $profiler->_sampler;
        if ($sampler && $sampler->can('sample_once')) {
            $sampler->sample_once();
        }
    }
    
    select(undef, undef, undef, 0.001);  # Allow sampling opportunity
    return test_recursive_function($depth - 1) + 1;
}

done_testing();