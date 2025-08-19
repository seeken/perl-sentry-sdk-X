#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# Integration test for structured logging with real Sentry DSN
# This test only runs if SENTRY_TEST_DSN is provided

plan skip_all => 'No SENTRY_TEST_DSN provided' unless $ENV{SENTRY_TEST_DSN};

use Sentry::SDK;
use Sentry::Logger;

my $test_dsn = $ENV{SENTRY_TEST_DSN};

# Initialize SDK with real DSN
Sentry::SDK->init({ dsn => $test_dsn });

subtest 'Real structured logging integration' => sub {
    plan tests => 3;
    
    # Create logger and send a test log
    my $logger = Sentry::Logger->new();
    $logger->info('Structured logging integration test from Perl SDK', {
        test_type => 'integration',
        timestamp => time(),
        sdk_version => $Sentry::SDK::VERSION,
        test_file => 'structured-logging-integration.t',
    });
    
    # Force flush
    my $sent_count = $logger->flush();
    ok($sent_count >= 0, 'Basic logging flush completed without error');
    
    # Test exception logging
    eval { die "Test exception for structured logging integration" };
    $logger->log_exception($@, 'error', {
        test_context => 'exception_test',
        error_type => 'intentional',
        test_suite => 'integration',
    });
    
    $sent_count = $logger->flush();
    ok($sent_count >= 0, 'Exception logging flush completed');
    
    # Test performance timing
    my $result = $logger->time_block('integration_performance_test', sub {
        sleep(1);  # Simulate work
        return 'integration performance test result';
    }, { 
        performance_test => 1,
        test_suite => 'integration',
    });
    
    is($result, 'integration performance test result', 'Performance test returned result');
    
    # Final flush
    $logger->flush();
    
    diag("Integration test completed - check Sentry dashboard for these log entries:");
    diag("  - 'Structured logging integration test from Perl SDK'");
    diag("  - 'Test exception for structured logging integration'");
    diag("  - Performance timing logs for 'integration_performance_test'");
};

done_testing();
