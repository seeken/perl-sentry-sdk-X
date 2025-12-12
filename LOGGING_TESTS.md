# Sentry Logging Test Scripts

## Valid and Recommended Tests

### 1. **test_simple_working.pl** ✅ RECOMMENDED
**Status**: Valid and fixed
**Purpose**: Simple, working test with correct API usage
**What it tests**:
- Simple message capture
- Message with structured data using `with_scope`
- Logger with structured data
- Exception capture

**Run**: `perl test_simple_working.pl`

**Best for**: Quick verification that logging is working with structured data

---

### 2. **test_verify_structured.pl** ✅ RECOMMENDED
**Status**: Valid and fixed
**Purpose**: Verify structured data appears correctly in Sentry
**What it tests**:
- Message with rich structured data using `configure_scope`
- Logger with nested structured data
- Proper use of tags, extra, user context

**Run**: `perl test_verify_structured.pl`

**Best for**: Confirming all your structured data shows up in Sentry UI

---

### 3. **test_live_logging.pl** ✅ VALID
**Status**: Valid (fixed earlier)
**Purpose**: Comprehensive logging feature test
**What it tests**:
- All log levels (trace, debug, info, warn, error, fatal)
- Template-based logging (sprintf)
- Contextual logging
- Exception logging
- Performance timing
- Structured data
- SDK logging methods

**Run**: `perl test_live_logging.pl`

**Best for**: Comprehensive test of all logging features

---

### 4. **test_breadcrumb_logs.pl** ✅ VALID
**Status**: Valid
**Purpose**: Test logs as breadcrumbs (alternative approach)
**What it tests**:
- Adding logs as breadcrumbs
- Breadcrumb timeline in events
- Structured data in breadcrumbs

**Run**: `perl test_breadcrumb_logs.pl`

**Best for**: Viewing logs as a timeline attached to events

---

### 5. **test_logging_diagnostic.pl** ✅ VALID
**Status**: Valid
**Purpose**: Diagnose logging issues
**What it tests**:
- Manual log record creation
- Different logging methods
- Buffer inspection
- Client methods

**Run**: `perl test_logging_diagnostic.pl`

**Best for**: Debugging when logs aren't appearing

---

## Experimental/Format Testing

### 6. **test_simple_event.pl** ⚠️ NEEDS UPDATE
**Status**: Needs fixing - has wrong `capture_message` usage
**Purpose**: Test simple event formats
**Action needed**: Update to use scope methods instead of passing context directly

---

### 7. **test_project_specific.pl** ⚠️ NEEDS UPDATE
**Status**: Needs fixing - has wrong `capture_message` usage
**Purpose**: Verify correct project ID targeting
**Action needed**: Update to use scope methods

---

### 8. **test_proper_format.pl** ✅ VALID
**Status**: Valid (experimental)
**Purpose**: Test different envelope formats
**What it tests**:
- Different envelope item types
- Format compatibility testing

**Run**: `perl test_proper_format.pl`

**Best for**: Testing what formats your Sentry version accepts

---

### 9. **test_logging_simplified.pl** ✅ VALID
**Status**: Valid
**Purpose**: Simplified logging test
**What it tests**:
- Basic log levels
- Simple structured data
- Flush verification

**Run**: `perl test_logging_simplified.pl`

**Best for**: Quick smoke test

---

## Profiling Tests (Not Logging-Related)

The following are profiling tests, not logging tests:
- `test_all_levels.pl`
- `test_basic_profiling.pl`
- `test_live_profiling.pl`
- `test_alarm_mechanism.pl`
- `test_profile_format_validation.pl`
- `test_profiling_mock_api.pl`
- `test_simple_profile.pl`

---

## Recommended Testing Order

1. **Start here**: `perl test_simple_working.pl`
   - Quick test to confirm logging works

2. **Verify data**: `perl test_verify_structured.pl`
   - Check that structured data appears in Sentry UI
   - Look for the test_id it prints
   - Click on events to see Extra/Additional Data section

3. **Full test**: `perl test_live_logging.pl`
   - Comprehensive test of all features

4. **Alternative view**: `perl test_breadcrumb_logs.pl`
   - See logs as breadcrumb timeline

---

## What to Look for in Sentry

After running tests, in your Sentry project:

1. **Issues/Messages section**: Your events will appear here
2. **Filter by environment**: Use the environment from the test (e.g., "simple-working")
3. **Click on an event** to see:
   - **Message**: The log message
   - **Tags**: Custom tags you set
   - **Extra/Additional Data**: All your structured data
   - **User Context**: User information
   - **Breadcrumbs**: Timeline of events (for breadcrumb tests)

---

## Known Issues

### No Dedicated "Logs" Page
- Your self-hosted Sentry may not have the newer "Logs" product
- Logs appear as **message events** in the Issues section
- This is normal and expected for many Sentry versions

### Project ID
- Tests send to project 9 by default
- Make sure you're viewing the correct project in the UI
- Don't confuse with project 1

### Structured Data Location
- Structured data appears in the "Extra" or "Additional Data" section
- Not in a separate logs view
- You must click on the event to see it

---

## Common Test Patterns

### Pattern 1: Message with Structured Data
```perl
Sentry::SDK->with_scope(sub {
    my $scope = shift;
    $scope->set_tag('key', 'value');
    $scope->set_extra('data', { nested => 'value' });

    Sentry::SDK->capture_message("Message", 'info');
});
```

### Pattern 2: Logger with Structured Data
```perl
my $logger = Sentry::SDK->get_logger();
$logger->error("Message", {
    key1 => 'value1',
    nested => { data => 'value' }
});
$logger->buffer->flush();
```

### Pattern 3: Breadcrumb Timeline
```perl
Sentry::SDK->add_breadcrumb({
    message => 'Log entry',
    category => 'log',
    level => 'info',
    data => { key => 'value' }
});

# Later, trigger an event
Sentry::SDK->capture_message("Event with breadcrumbs", 'error');
```
