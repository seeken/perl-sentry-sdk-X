# Phase 2 Implementation: Cron Monitoring

**Status**: ✅ **COMPLETED**  
**Implementation Date**: August 14, 2025

## Overview

Phase 2 successfully implements comprehensive cron monitoring capabilities for the Perl Sentry SDK, enabling developers to monitor scheduled jobs, background tasks, and cron jobs with detailed check-ins and monitor configurations.

## Features Implemented

### 1. Check-in API (`Sentry::Crons::CheckIn`)

- **Auto-generated UUIDs** for check-in tracking
- **Status management**: `in_progress`, `ok`, `error`, `timeout`
- **Duration tracking** in milliseconds
- **Environment support** for multi-environment monitoring
- **Context data** for additional metadata
- **Envelope serialization** for Sentry API v7

### 2. Monitor Configuration (`Sentry::Crons::Monitor`)

- **Crontab schedule** support (e.g., `0 2 * * *`)
- **Interval schedule** support (e.g., every 30 minutes)
- **Timezone support** with customizable timezones
- **Grace periods** with configurable check-in margins
- **Runtime limits** with maximum execution time
- **Failure thresholds** for issue creation
- **Validation** with comprehensive error checking

### 3. High-Level SDK API

#### Manual Check-in Management
```perl
# Start a check-in
my $check_in_id = Sentry::SDK->capture_check_in({
    monitor_slug => 'daily-backup',
    status => 'in_progress',
    environment => 'production',
});

# Update on completion
Sentry::SDK->update_check_in($check_in_id, 'ok', 30000);
```

#### Automatic Monitoring
```perl
# Wrap your job with automatic monitoring
Sentry::SDK->with_monitor('backup-job', sub {
    # Your cron job code here
    perform_backup();
});
```

#### Monitor Configuration
```perl
# Create or update monitor configuration
Sentry::SDK->upsert_monitor({
    slug => 'daily-backup',
    name => 'Daily Database Backup',
    schedule => {
        type => 'crontab',
        value => '0 2 * * *',  # Daily at 2 AM
    },
    checkin_margin => 10,  # 10 minutes grace period
    max_runtime => 60,     # 60 minutes max runtime
    timezone => 'UTC',
});
```

### 4. Core Module (`Sentry::Crons`)

- **Active check-in tracking** with memory management
- **Exception handling** with automatic error status
- **Multi-environment support** for staging/production
- **Cleanup utilities** for long-running processes
- **Direct API access** for advanced use cases

## Technical Implementation

### Envelope Integration

Phase 2 builds on the enhanced envelope support from Phase 1:

- **Check-in items**: `type: "check_in"` with complete metadata
- **Monitor items**: `type: "monitor"` with configuration data
- **Multi-item envelopes**: Support for batching different item types
- **HTTP transport**: Seamless integration with existing transport layer

### Error Handling

- **Automatic status detection**: Success/failure based on exceptions
- **Context preservation**: Monitor slug tracking for updates
- **Graceful degradation**: Continue execution if Sentry is unavailable
- **Validation**: Comprehensive input validation with helpful errors

### Memory Management

- **Active tracking**: In-memory tracking of in-progress check-ins
- **Automatic cleanup**: Removal of completed check-ins
- **Stale detection**: Cleanup of orphaned check-ins
- **Resource efficiency**: Minimal memory footprint

## Usage Examples

### Real-world Cron Job
```perl
#!/usr/bin/env perl
use Sentry::SDK;

Sentry::SDK->init({
    dsn => $ENV{SENTRY_DSN},
    environment => 'production',
});

# Configure the monitor (run once)
Sentry::SDK->upsert_monitor({
    slug => 'user-cleanup',
    name => 'Daily User Cleanup',
    schedule => { type => 'crontab', value => '0 3 * * *' },
    checkin_margin => 5,
    max_runtime => 30,
});

# Monitor the actual job execution
Sentry::SDK->with_monitor('user-cleanup', sub {
    cleanup_inactive_users();
    send_summary_email();
});
```

### Background Processing
```perl
use Sentry::Crons;

# Direct API for more control
my $checkin = Sentry::Crons::CheckIn->new(
    monitor_slug => 'email-queue',
    status => 'in_progress',
    environment => 'production',
);

$checkin->add_context('queue_size', scalar(@emails));
$checkin->add_context('worker_id', $$);

my $check_in_id = Sentry::Crons->capture_check_in($checkin);

eval {
    process_email_queue(@emails);
};

if ($@) {
    $checkin->mark_error();
    logger->error("Email processing failed: $@");
} else {
    $checkin->mark_ok();
}

Sentry::Crons->capture_check_in($checkin);
```

## Files Created/Modified

### New Files
- `lib/Sentry/Crons.pm` - Main cron monitoring module
- `lib/Sentry/Crons/CheckIn.pm` - Check-in data structure
- `lib/Sentry/Crons/Monitor.pm` - Monitor configuration
- `t/crons.t` - Comprehensive test suite
- `examples/phase2_demo.pl` - Feature demonstration

### Modified Files
- `lib/Sentry/SDK.pm` - Added cron monitoring methods and documentation
- `lib/Sentry/Client.pm` - Added envelope support methods
- `lib/Sentry/Transport/Http.pm` - Added send_envelope method

## Testing

### Test Coverage
- **Unit tests**: All classes and methods
- **Integration tests**: SDK method integration
- **Error handling**: Invalid inputs and edge cases
- **Mock transport**: Envelope verification without network calls
- **Real Sentry testing**: Set `SENTRY_TEST_DSN` for integration with real Sentry instance
- **Exception handling**: Automatic error detection

### Test Results
```
t/crons.t .......................... ok
All Phase 2 tests passing: 9/9 subtests
```

### Real Integration Testing

The test suite supports real integration testing with a live Sentry instance:

```bash
# Mock testing (default)
perl -Ilib t/crons.t

# Real integration testing
export SENTRY_TEST_DSN="https://your_key@sentry.io/your_project"
perl -Ilib t/crons.t

# Or use the helper script
./examples/test_crons.sh
```

When using a real DSN, the test will:
- Send actual check-ins and monitor configurations to Sentry
- Verify HTTP 200 responses instead of mocked responses
- Add diagnostic messages about data being sent
- Include brief delays to allow Sentry processing

## Integration with Existing Features

### Phase 1 Compatibility
- **Enhanced envelopes**: Builds on Phase 1 envelope system
- **Rate limiting**: Respects existing rate limit infrastructure
- **Backpressure**: Integrates with backpressure management
- **Client options**: Works with enhanced client configuration

### Framework Integration
- **Mojolicious**: Compatible with existing plugin
- **CGI::Application**: Compatible with existing plugin
- **Standalone scripts**: Perfect for cron jobs and background tasks

## Performance Characteristics

- **Low overhead**: Minimal impact on job execution
- **Async transport**: Non-blocking network requests
- **Memory efficient**: Automatic cleanup of completed check-ins
- **Resilient**: Continues execution if Sentry is unavailable

## Next Steps

Phase 2 provides a solid foundation for cron monitoring. Future enhancements could include:

- **Batch check-ins**: Multiple check-ins in single envelope
- **Heartbeat monitoring**: Periodic alive signals
- **Metric collection**: Performance metrics for monitored jobs
- **Alert integration**: Direct integration with alerting systems

## Conclusion

Phase 2 successfully delivers enterprise-grade cron monitoring capabilities, making the Perl Sentry SDK competitive with modern SDKs in other languages. The implementation is robust, well-tested, and ready for production use.
