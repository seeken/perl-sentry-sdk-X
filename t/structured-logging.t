use Test::More;
use Test::MockModule;
use strict;
use warnings;

use lib 't/lib';
use Mock::Sentry::Hub;
use Mock::Sentry::Client;
use Mock::Sentry::Transport::HTTP;

# Test the structured logging components
use_ok('Sentry::Logger::LogRecord');
use_ok('Sentry::Logger::Buffer');
use_ok('Sentry::Logger');

# Mock Sentry::Hub for consistent testing
my $hub_mock = Test::MockModule->new('Sentry::Hub');
my $mock_hub = Mock::Sentry::Hub->new();
$hub_mock->mock('get_current_hub', sub { $mock_hub });

# Mock Sentry::Client to track envelopes
my $client_mock = Test::MockModule->new('Sentry::Client');
my $mock_client = Mock::Sentry::Client->new();
$mock_hub->client($mock_client);

subtest 'LogRecord creation and serialization' => sub {
    my $record = Sentry::Logger::LogRecord->new(
        level => 'info',
        message => 'Test message',
        context => { user_id => 123, action => 'login' },
        timestamp => 1234567890.123,
    );
    
    ok($record, 'LogRecord created');
    is($record->level, 'info', 'Level set correctly');
    is($record->message, 'Test message', 'Message set correctly');
    is($record->timestamp, 1234567890.123, 'Timestamp set correctly');
    
    my $envelope_item = $record->to_envelope_item();
    ok($envelope_item, 'Envelope item created');
    is($envelope_item->{level}, 'info', 'Envelope level correct');
    is($envelope_item->{message}, 'Test message', 'Envelope message correct');
    is($envelope_item->{user_id}, 123, 'Context included in envelope');
    is($envelope_item->{action}, 'login', 'Context values preserved');
    
    # Test severity levels
    my $trace_record = Sentry::Logger::LogRecord->new(level => 'trace', message => 'test');
    my $debug_record = Sentry::Logger::LogRecord->new(level => 'debug', message => 'test');
    my $info_record = Sentry::Logger::LogRecord->new(level => 'info', message => 'test');
    my $warn_record = Sentry::Logger::LogRecord->new(level => 'warn', message => 'test');
    my $error_record = Sentry::Logger::LogRecord->new(level => 'error', message => 'test');
    my $fatal_record = Sentry::Logger::LogRecord->new(level => 'fatal', message => 'test');
    
    is($trace_record->severity_number, 1, 'TRACE severity correct');
    is($debug_record->severity_number, 5, 'DEBUG severity correct');
    is($info_record->severity_number, 9, 'INFO severity correct');
    is($warn_record->severity_number, 13, 'WARN severity correct');
    is($error_record->severity_number, 17, 'ERROR severity correct');
    is($fatal_record->severity_number, 21, 'FATAL severity correct');
};

subtest 'Buffer functionality' => sub {
    my $buffer = Sentry::Logger::Buffer->new(
        max_size => 3,
        flush_interval => 60,
        min_level => 'debug',
        auto_flush => 0,  # Disable auto-flush for testing
    );
    
    ok($buffer, 'Buffer created');
    is(scalar @{$buffer->records}, 0, 'Buffer starts empty');
    
    # Add some records
    my $record1 = Sentry::Logger::LogRecord->new(level => 'debug', message => 'Debug msg');
    my $record2 = Sentry::Logger::LogRecord->new(level => 'info', message => 'Info msg');
    my $record3 = Sentry::Logger::LogRecord->new(level => 'error', message => 'Error msg');
    
    $buffer->add($record1);
    $buffer->add($record2);
    $buffer->add($record3);
    
    is(scalar @{$buffer->records}, 3, 'All records added');
    
    # Test filtering
    my $error_records = $buffer->filter_by_level('error');
    is(scalar @$error_records, 1, 'Error filter works');
    is($error_records->[0]->message, 'Error msg', 'Correct error record');
    
    my $info_plus = $buffer->filter_by_level('info');
    is(scalar @$info_plus, 2, 'Info+ filter includes info and error');
    
    # Test stats
    my $stats = $buffer->stats();
    is($stats->{record_count}, 3, 'Stats show correct count');
    is($stats->{min_level}, 'debug', 'Stats show correct min level');
    
    # Test manual flush (mocked)
    my $sent_count = $buffer->flush();
    is($sent_count, 3, 'Flush returns correct count');
    is(scalar @{$buffer->records}, 0, 'Buffer cleared after flush');
};

subtest 'Logger core functionality' => sub {
    # Clear any previous state
    $mock_client->clear_envelopes();
    
    my $logger = Sentry::Logger->new();
    # Disable auto-flush for testing
    $logger->buffer->auto_flush(0);
    # Set min level to trace to capture all logs
    $logger->buffer->min_level('trace');
    ok($logger, 'Logger created');
    
    # Test basic logging
    my $record = $logger->log('info', 'Test log message', { key => 'value' });
    ok($record, 'Log record returned');
    is($record->level, 'info', 'Record level correct');
    is($record->message, 'Test log message', 'Record message correct');
    
    # Test convenience methods
    $logger->debug('Debug message');
    $logger->info('Info message');
    $logger->warn('Warning message');
    $logger->error('Error message');
    $logger->fatal('Fatal message');
    
    # Check buffer has records
    my $buffer_count = scalar @{$logger->buffer->records};
    is($buffer_count, 6, 'All log calls created records');
    
    # Test template logging
    $logger->logf('info', 'User %s performed %s', 'john', 'login', { session_id => 'abc123' });
    
    # Test context methods
    $logger->set_context({ service => 'auth' });
    $logger->add_context({ version => '1.0' });
    $logger->info('Service message');
    
    my $last_record = $logger->buffer->records->[-1];
    is($last_record->context->{service}, 'auth', 'Service context set');
    is($last_record->context->{version}, '1.0', 'Version context added');
    
    # Test contextual logger
    my $contextual = $logger->with_context({ request_id => 'req-123' });
    $contextual->info('Request processed');
    
    my $contextual_record = $contextual->buffer->records->[-1];
    is($contextual_record->context->{request_id}, 'req-123', 'Contextual logger works');
    is($contextual_record->context->{service}, 'auth', 'Original context preserved');
    
    $logger->clear_context();
    is_deeply($logger->context, {}, 'Context cleared');
};

subtest 'Logger template methods' => sub {
    my $logger = Sentry::Logger->new();
    # Disable auto-flush for testing
    $logger->buffer->auto_flush(0);
    # Set min level to trace to capture all logs
    $logger->buffer->min_level('trace');
    $logger->buffer->clear();
    
    # Test all template methods
    $logger->tracef('Trace: %s', 'test');
    $logger->debugf('Debug: %d items', 5);
    $logger->infof('Info: %s completed', 'operation');
    $logger->warnf('Warning: %s threshold exceeded', 'memory');
    $logger->errorf('Error: %s failed', 'connection');
    $logger->fatalf('Fatal: %s corrupted', 'database');
    
    my $records = $logger->buffer->records;
    is(scalar @$records, 6, 'All template methods created records');
    is($records->[0]->message, 'Trace: test', 'Trace template worked');
    is($records->[1]->message, 'Debug: 5 items', 'Debug template worked');
    is($records->[2]->message, 'Info: operation completed', 'Info template worked');
    is($records->[3]->message, 'Warning: memory threshold exceeded', 'Warn template worked');
    is($records->[4]->message, 'Error: connection failed', 'Error template worked');
    is($records->[5]->message, 'Fatal: database corrupted', 'Fatal template worked');
};

subtest 'Exception logging' => sub {
    my $logger = Sentry::Logger->new();
    $logger->buffer->clear();
    
    my $exception = "Database connection failed";
    my $record = $logger->log_exception($exception, 'error', { database => 'users' });
    
    ok($record, 'Exception record created');
    is($record->level, 'error', 'Exception level correct');
    like($record->message, qr/Exception: Database connection failed/, 'Exception message formatted');
    is($record->context->{exception}, $exception, 'Exception in context');
    is($record->context->{database}, 'users', 'Additional context preserved');
};

subtest 'Performance timing' => sub {
    my $logger = Sentry::Logger->new();
    # Set min level to debug to capture start messages
    $logger->buffer->min_level('debug');
    $logger->buffer->clear();
    
    my $result = $logger->time_block('test_operation', sub {
        return 'operation result';
    }, { operation_id => 'op123' });
    
    is($result, 'operation result', 'Time block returns result');
    
    my $records = $logger->buffer->records;
    is(scalar @$records, 2, 'Time block created start and end records');
    
    like($records->[0]->message, qr/Starting: test_operation/, 'Start message correct');
    like($records->[1]->message, qr/Completed: test_operation/, 'Completion message correct');
    
    is($records->[0]->context->{operation}, 'test_operation', 'Start context correct');
    is($records->[1]->context->{operation}, 'test_operation', 'End context correct');
    ok(exists $records->[1]->context->{duration_ms}, 'Duration recorded');
    is($records->[1]->context->{operation_id}, 'op123', 'Additional context preserved');
};

subtest 'Singleton logger' => sub {
    my $logger1 = Sentry::Logger->logger();
    my $logger2 = Sentry::Logger->logger();
    
    is($logger1, $logger2, 'Singleton returns same instance');
    
    # Test class method shortcuts
    Sentry::Logger->class_info('Class method test');
    
    my $records = $logger1->buffer->records;
    ok(scalar @$records > 0, 'Class method created record');
    
    my $last_record = $records->[-1];
    is($last_record->message, 'Class method test', 'Class method message correct');
    is($last_record->level, 'info', 'Class method level correct');
};

subtest 'Configuration and control' => sub {
    my $logger = Sentry::Logger->new();
    
    # Test enable/disable
    $logger->disable();
    ok(!$logger->enabled, 'Logger disabled');
    
    $logger->buffer->clear();
    $logger->info('Should not log');
    is(scalar @{$logger->buffer->records}, 0, 'Disabled logger ignores calls');
    
    $logger->enable();
    ok($logger->enabled, 'Logger re-enabled');
    
    $logger->info('Should log');
    is(scalar @{$logger->buffer->records}, 1, 'Enabled logger works');
    
    # Test configuration
    $logger->configure({
        enabled => 0,
        buffer => { max_size => 50, min_level => 'warn' }
    });
    
    ok(!$logger->enabled, 'Configuration disabled logger');
    is($logger->buffer->max_size, 50, 'Buffer max_size configured');
    is($logger->buffer->min_level, 'warn', 'Buffer min_level configured');
    
    # Test stats
    my $stats = $logger->stats();
    ok(exists $stats->{enabled}, 'Stats include enabled');
    ok(exists $stats->{buffer}, 'Stats include buffer info');
};

subtest 'Integration with SDK' => sub {
    # Test SDK logging methods
    use_ok('Sentry::SDK');
    
    # These should not die (methods exist)
    eval {
        my $logger = Sentry::SDK->get_logger();
        ok($logger, 'SDK get_logger works');
        
        Sentry::SDK->log('info', 'SDK test message');
        Sentry::SDK->log_info('SDK info message', { test => 1 });
        Sentry::SDK->logf('info', 'SDK template %s', 'test');
        
        my $contextual = Sentry::SDK->with_log_context({ sdk_test => 1 });
        ok($contextual, 'SDK with_log_context works');
    };
    
    ok(!$@, 'SDK logging methods work') or diag("Error: $@");
};

# Test with real DSN if available (optional)
subtest 'Real integration test' => sub {
    my $test_dsn = $ENV{SENTRY_TEST_DSN};
    
    SKIP: {
        skip 'No SENTRY_TEST_DSN provided - use t/structured-logging-integration.t for real testing', 3 unless $test_dsn;
        
        # Note: Real integration testing is now in a separate test file
        # to avoid interference with mocked tests
        pass('Real integration test available in structured-logging-integration.t');
        pass('Run with SENTRY_TEST_DSN to test real integration');
        pass('Check structured-logging-integration.t for actual integration tests');
        
        diag("For real integration testing, run:");
        diag("SENTRY_TEST_DSN=your_dsn perl t/structured-logging-integration.t");
    };
};

done_testing();
