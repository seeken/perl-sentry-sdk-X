use Mojo::Base -strict, -signatures;
use Test::More;
use Test::Exception;

use lib 'lib';
use Sentry::SDK;
use Sentry::Profiling;
use Sentry::Profiling::Profile;
use Sentry::Profiling::Frame;

# Test Frame creation and serialization
subtest 'Frame functionality' => sub {
    my $frame = Sentry::Profiling::Frame->from_caller_info(
        'MyApp::Service', '/path/to/service.pm', 42, 'MyApp::Service::process'
    );
    
    isa_ok($frame, 'Sentry::Profiling::Frame', 'Frame created correctly');
    is($frame->package, 'MyApp::Service', 'Package set correctly');
    is($frame->filename, '/path/to/service.pm', 'Filename set correctly');
    is($frame->lineno, 42, 'Line number set correctly');
    is($frame->function, 'process', 'Function name cleaned correctly');
    
    my $hash = $frame->to_hash();
    ok($hash, 'Frame converts to hash');
    is($hash->{function}, 'process', 'Hash function correct');
    is($hash->{lineno}, 42, 'Hash line number correct');
    
    my $sig = $frame->signature();
    ok($sig, 'Frame has signature');
    like($sig, qr/MyApp::Service.*service\.pm.*42.*process/, 'Signature contains key components');
};

# Test Profile data structure
subtest 'Profile functionality' => sub {
    my $profile = Sentry::Profiling::Profile->new(
        name => 'test-profile',
        transaction_id => 'txn-123',
        trace_id => 'trace-456',
    );
    
    isa_ok($profile, 'Sentry::Profiling::Profile', 'Profile created correctly');
    is($profile->name, 'test-profile', 'Profile name set');
    
    # Test adding samples
    my $sample = {
        timestamp => time(),
        thread_id => "$$",
        frames => [
            {
                package => 'main',
                filename => 'test.pl',
                lineno => 10,
                function => 'main',
                in_app => 1,
            },
            {
                package => 'MyApp',
                filename => 'lib/MyApp.pm',
                lineno => 25,
                function => 'process',
                in_app => 1,
            }
        ]
    };
    
    $profile->add_sample($sample);
    is($profile->get_sample_count(), 1, 'Sample added to profile');
    
    $profile->finish();
    ok($profile->end_time, 'Profile finished with end time');
    
    my $envelope = $profile->to_envelope_item();
    ok($envelope, 'Profile converts to envelope');
    is($envelope->{type}, 'profile', 'Envelope has correct type');
    ok($envelope->{profile}, 'Envelope contains profile data');
    ok($envelope->{transaction}, 'Envelope contains transaction data');
    
    my $stats = $profile->get_stats();
    is($stats->{sample_count}, 1, 'Stats show correct sample count');
    ok($stats->{unique_frames} > 0, 'Stats show unique frames');
};

# Test Profiler configuration
subtest 'Profiler configuration' => sub {
    my $profiler = Sentry::Profiling->new(
        enable_profiling => 1,
        profiles_sample_rate => 0.5,
        sampling_interval_us => 5000,
    );
    
    isa_ok($profiler, 'Sentry::Profiling', 'Profiler created');
    ok($profiler->enable_profiling, 'Profiling enabled');
    is($profiler->profiles_sample_rate, 0.5, 'Sample rate set');
    is($profiler->sampling_interval_us, 5000, 'Sampling interval set');
    
    ok(!$profiler->is_profiling_active(), 'Not profiling initially');
    
    # Test disabled profiler
    my $disabled_profiler = Sentry::Profiling->new(enable_profiling => 0);
    my $profile = $disabled_profiler->start_profiler({ name => 'test' });
    ok(!$profile, 'No profile when disabled');
};

# Test SDK profiling methods (without actual sampling)
subtest 'SDK profiling API' => sub {
    # Test with no DSN (should gracefully handle missing client)
    Sentry::SDK->init({});
    
    ok(!Sentry::SDK->is_profiling_active(), 'Not profiling without client');
    
    my $profile = Sentry::SDK->start_profiler({ name => 'test' });
    ok(!$profile, 'No profiling without valid client');
    
    my $profiler = Sentry::SDK->get_profiler();
    ok(!$profiler, 'No profiler without valid client');
};

# Test transaction integration structure
subtest 'Transaction profiling structure' => sub {
    Sentry::SDK->init({
        dsn => 'https://key@sentry.io/1',
        enable_profiling => 1,
        profiles_sample_rate => 1.0,
    });
    
    # Create a transaction to test structure
    my $transaction = Sentry::SDK->start_transaction({
        name => 'test-transaction',
        op => 'test',
    });
    
    ok($transaction, 'Transaction created');
    ok($transaction->can('start_profiling'), 'Transaction has profiling method');
    ok($transaction->can('_profile'), 'Transaction has profile attribute');
};

done_testing();