# Perl Sentry SDK Modernization Plan

**Version**: 1.0  
**Date**: August 14, 2025  
**Current SDK Version**: 1.3.9  
**Target Sentry API Version**: Latest (v7+)

## Executive Summary

This document outlines a comprehensive plan to modernize the Perl Sentry SDK by implementing recent Sentry API features and improving the overall architecture. The plan is designed to maintain backward compatibility while adding support for modern observability features including cron monitoring, profiling, user feedback, attachments, and enhanced error tracking.

## Current Status Assessment

### ✅ Currently Implemented Features

- **Error Capture**: `capture_exception`, `capture_message`, `capture_event`
- **Performance Monitoring**: Transactions and spans with proper instrumentation
- **Breadcrumb Tracking**: Manual and automatic breadcrumb collection
- **Scope Management**: Tags, user context, and scope configuration
- **Enhanced Envelope Support**: Multi-item envelope transport system ✅ **PHASE 1 COMPLETE**
- **HTTP Transport**: Proper authentication with Sentry API v7
- **Framework Integrations**: 
  - Mojolicious (`Mojolicious::Plugin::SentrySDK`)
  - CGI::Application (`CGI::Application::Plugin::Sentry`)
  - DBI integration for database monitoring ✅ **ENHANCED WITH OPENTELEMETRY**
  - LWP and Mojo UserAgent integrations ✅ **ENHANCED WITH OPENTELEMETRY**
- **Source Context**: Stack traces with source file registry
- **Environment Configuration**: Support for environment variables
- **Rate Limiting**: HTTP 429 and X-Sentry-Rate-Limits header handling ✅ **PHASE 1 COMPLETE**
- **Backpressure Management**: Dynamic sampling under load ✅ **PHASE 1 COMPLETE**
- **Enhanced Client Options**: Advanced configuration and filtering ✅ **PHASE 1 COMPLETE**
- **Cron Monitoring**: Check-ins for scheduled job monitoring ✅ **PHASE 2 COMPLETE**

### ❌ Missing Modern Features

The following features are available in modern Sentry SDKs but missing from the Perl implementation:

- **Structured Logging**: New Sentry logging API for structured log collection and analysis
- **User Feedback**: Widget and crash report modal support
- **Session Replay**: Web session recording capabilities
- **Attachments**: File attachment support for events
- **Offline Caching**: Event persistence for unreliable networks
- **HTTP Client Error Capture**: Automatic failed request monitoring
- **GraphQL Monitoring**: GraphQL-specific error and performance tracking
- **Feature Flag Tracking**: Feature flag evaluation logging
- **Startup Crash Detection**: Early crash detection and reporting

## Implementation Plan

### Phase 1: Core Infrastructure Improvements ✅ **COMPLETED**

**Priority**: High  
**Dependencies**: None  
**Risk**: Low  
**Status**: ✅ **COMPLETED - All objectives achieved**

#### 1.1 Enhanced Envelope Support ✅

**Objective**: Expand envelope system to support multiple item types beyond transactions.

**Implementation Status**: ✅ **COMPLETED**
- Enhanced `lib/Sentry/Envelope.pm` with `add_item()` and `get_items()` methods
- Updated `lib/Sentry/Transport/Http.pm` to support new envelope format
- Maintained backward compatibility with existing code
- All tests passing

#### 1.2 Integration System Fixes and Enhancements ✅

**Objective**: Fix the bug where custom integrations are not properly initialized and enhance existing integrations with missing telemetry data.

**Implementation Status**: ✅ **COMPLETED**
- Fixed critical bug in `lib/Sentry/SDK.pm` where `setup_integrations()` was never called
- Enhanced DBI integration with OpenTelemetry-compliant database telemetry
- Enhanced LWP and Mojo UserAgent integrations with HTTP client telemetry
- Added selective integration disabling support
- All integrations now properly auto-load and initialize

#### 1.3 Rate Limiting and Backpressure Management ✅

**Objective**: Implement proper rate limiting with HTTP 429 and X-Sentry-Rate-Limits header handling, plus backpressure management for high-load scenarios.

**Implementation Status**: ✅ **COMPLETED**
- Created `lib/Sentry/RateLimit.pm` for HTTP 429 and rate limit header handling
- Created `lib/Sentry/Backpressure.pm` for dynamic sampling under load
- Integrated rate limiting into `lib/Sentry/Transport/Http.pm`
- Added queue size tracking and pressure-based event dropping
- All tests passing

#### 1.4 Enhanced Client Options ✅

**Objective**: Implement comprehensive client configuration options for production use.

**Implementation Status**: ✅ **COMPLETED**
- Added `max_request_body_size` with size presets (never/always/small/medium/large)
- Added `send_default_pii` option with automatic PII scrubbing
- Added `capture_failed_requests` with status code and URL pattern filtering
- Added `ignore_errors` and `ignore_transactions` with pattern/callback support
- Added `offline_storage_path` for event persistence during network issues
- Added comprehensive PII filtering for headers, user data, and context
- All tests passing

**Files to Modify**:
- `lib/Sentry/Envelope.pm`
- `lib/Sentry/Transport/Http.pm`

**Implementation Details**:
```perl
# Enhanced envelope with multiple item support
package Sentry::Envelope;

has items => sub { [] };  # Array of envelope items

sub add_item ($self, $type, $data, $headers = {}) {
    push $self->items->@*, {
        headers => { type => $type, %$headers },
        payload => $data
    };
}

sub serialize ($self) {
    my @lines = (encode_json($self->headers));
    
    for my $item ($self->items->@*) {
        push @lines, encode_json($item->{headers});
        push @lines, ref($item->{payload}) ? encode_json($item->{payload}) : $item->{payload};
    }
    
    return join("\n", @lines);
}
```

**Testing Requirements**:
- Unit tests for envelope serialization
- Integration tests with various item types
- Backward compatibility verification

#### 1.2 Integration System Fixes and Enhancements

**Objective**: Fix the bug where custom integrations are not properly initialized and enhance existing integrations with missing telemetry data.

**Critical Bug Fix**:
The current issue is in `lib/Sentry/SDK.pm` where `setup_integrations()` is never called after the client is created.

**Files to Modify**:
- `lib/Sentry/SDK.pm` - Fix integration setup
- `lib/Sentry/Integration.pm` - Improve integration handling
- `lib/Sentry/Integration/DBI.pm` - Add missing database telemetry
- `lib/Sentry/Integration/LwpUserAgent.pm` - Add missing HTTP telemetry
- `lib/Sentry/Integration/MojoUserAgent.pm` - Add missing HTTP telemetry
- `lib/Sentry/Integration/MojoTemplate.pm` - Add missing template telemetry

**Bug Fix Implementation**:
```perl
# Fixed lib/Sentry/SDK.pm
sub _init_and_bind ($options) {
  my $hub = Sentry::Hub->get_current_hub();
  my $client = $options->{dsn} ? Sentry::Client->new(_options => $options) : undef;
  
  if ($client) {
    $hub->bind_client($client);
    
    # FIX: Actually call setup_integrations after client is bound
    $client->setup_integrations();
  }
}

sub init ($package, $options = {}) {
  # Set default integrations if not explicitly disabled
  $options->{default_integrations} //= 1;
  $options->{integrations} //= [];
  
  # Add built-in integrations unless disabled
  if ($options->{default_integrations}) {
    # Allow selective disabling of built-in integrations
    my %disabled = map { $_ => 1 } @{$options->{disabled_integrations} // []};
    
    unless ($disabled{DieHandler}) {
      push @{$options->{integrations}}, Sentry::Integration::DieHandler->new;
    }
    unless ($disabled{DBI}) {
      push @{$options->{integrations}}, Sentry::Integration::DBI->new;
    }
    unless ($disabled{LwpUserAgent}) {
      push @{$options->{integrations}}, Sentry::Integration::LwpUserAgent->new;
    }
    unless ($disabled{MojoUserAgent}) {
      push @{$options->{integrations}}, Sentry::Integration::MojoUserAgent->new;
    }
    unless ($disabled{MojoTemplate}) {
      push @{$options->{integrations}}, Sentry::Integration::MojoTemplate->new;
    }
  }
  
  # Existing initialization code...
  $options->{dsn} //= $ENV{SENTRY_DSN};
  # ... rest of init
  
  _init_and_bind($options);
}
```

**Enhanced Integration Implementation**:
```perl
# Fixed lib/Sentry/Integration.pm
package Sentry::Integration;

# Remove global integrations - these should be managed through client options
sub setup ($package, $integrations = []) {
  foreach my $integration (grep { !$_->initialized } @$integrations) {
    $integration->setup_once(
      Sentry::Hub::Scope->can('add_global_event_processor'),
      Sentry::Hub->can('get_current_hub')
    );
    $integration->initialized(1);
  }
}
```

**Enhanced DBI Integration with Complete Telemetry**:
```perl
# Enhanced lib/Sentry/Integration/DBI.pm
package Sentry::Integration::DBI;

sub setup_once ($self, $add_global_event_processor, $get_current_hub) {
  return if (!$self->breadcrumbs && !$self->tracing);

  # Enhanced DBI::db->do method
  around('DBI::db', do => sub ($orig, $dbh, $statement, @args) {
    my $hub = $get_current_hub->();
    my $span;

    if ($self->tracing && (my $parent_span = $hub->get_scope()->get_span)) {
      # Parse statement to get operation
      my $operation = $self->_extract_sql_operation($statement);
      my $table = $self->_extract_table_name($statement);
      
      $span = $parent_span->start_child({
        op => 'db.query',
        description => $self->_truncate_sql($statement),
        data => {
          # OpenTelemetry semantic conventions
          'db.system' => $self->_get_db_system($dbh),
          'db.operation' => $operation,
          'db.collection.name' => $table,
          'db.name' => $dbh->{Name} // 'unknown',
          'server.address' => $self->_extract_host($dbh),
          'server.port' => $self->_extract_port($dbh),
          
          # Additional context
          'db.statement' => $self->_should_capture_statement() ? $statement : undef,
          'db.connection_id' => $dbh,
          'thread.id' => threads->tid() // $$,
        },
      });
    }

    my $start_time = Time::HiRes::time();
    my $value = $orig->($dbh, $statement, @args);
    my $duration = Time::HiRes::time() - $start_time;

    # Enhanced breadcrumb with more context
    $hub->add_breadcrumb({
      type => 'query',
      category => 'db.query',
      message => $self->_truncate_sql($statement),
      level => 'info',
      data => {
        'db.system' => $self->_get_db_system($dbh),
        'db.operation' => $self->_extract_sql_operation($statement),
        'db.collection.name' => $self->_extract_table_name($statement),
        'duration_ms' => int($duration * 1000),
        'rows_affected' => $value // 0,
      },
    }) if $self->breadcrumbs;

    if ($span) {
      $span->set_data('db.rows_affected', $value // 0);
      $span->set_data('duration_ms', int($duration * 1000));
      $span->finish();
    }

    return $value;
  });

  # Enhanced DBI::st->execute method
  around('DBI::st', execute => sub ($orig, $sth, @args) {
    my $statement = $sth->{Statement};
    my $hub = $get_current_hub->();
    my $span;

    if ($self->tracing && (my $parent_span = $hub->get_scope()->get_span)) {
      my $operation = $self->_extract_sql_operation($statement);
      my $table = $self->_extract_table_name($statement);
      
      $span = $parent_span->start_child({
        op => 'db.query',
        description => $self->_truncate_sql($statement),
        data => {
          'db.system' => $self->_get_db_system($sth->{Database}),
          'db.operation' => $operation,
          'db.collection.name' => $table,
          'db.name' => $sth->{Database}->{Name} // 'unknown',
          'server.address' => $self->_extract_host($sth->{Database}),
          'server.port' => $self->_extract_port($sth->{Database}),
          'db.statement' => $self->_should_capture_statement() ? $statement : undef,
          'db.parameter_count' => scalar(@args),
          'thread.id' => threads->tid() // $$,
        },
      });
    }

    my $start_time = Time::HiRes::time();
    my $value = $orig->($sth, @args);
    my $duration = Time::HiRes::time() - $start_time;

    $hub->add_breadcrumb({
      type => 'query',
      category => 'db.query',
      message => $self->_truncate_sql($statement),
      level => 'info',
      data => {
        'db.system' => $self->_get_db_system($sth->{Database}),
        'db.operation' => $self->_extract_sql_operation($statement),
        'db.collection.name' => $self->_extract_table_name($statement),
        'duration_ms' => int($duration * 1000),
        'rows_affected' => $sth->rows // 0,
        'parameter_count' => scalar(@args),
      },
    }) if $self->breadcrumbs;

    if ($span) {
      $span->set_data('db.rows_affected', $sth->rows // 0);
      $span->set_data('duration_ms', int($duration * 1000));
      $span->finish();
    }

    return $value;
  });
}

# Helper methods for database telemetry
sub _get_db_system ($self, $dbh) {
  my $driver = $dbh->{Driver}->{Name} // 'unknown';
  return {
    'mysql' => 'mysql',
    'Pg' => 'postgresql',
    'SQLite' => 'sqlite',
    'Oracle' => 'oracle',
    'ODBC' => 'mssql',
  }->{$driver} // lc($driver);
}

sub _extract_sql_operation ($self, $sql) {
  return 'unknown' unless $sql;
  if ($sql =~ /^\s*(SELECT|INSERT|UPDATE|DELETE|CREATE|DROP|ALTER|TRUNCATE)\b/i) {
    return uc($1);
  }
  return 'unknown';
}

sub _extract_table_name ($self, $sql) {
  return undef unless $sql;
  # Simple regex to extract table name - can be enhanced
  if ($sql =~ /(?:FROM|INTO|UPDATE|TABLE)\s+`?(\w+)`?/i) {
    return $1;
  }
  return undef;
}

sub _extract_host ($self, $dbh) {
  my $name = $dbh->{Name} // '';
  if ($name =~ /host=([^;]+)/i) {
    return $1;
  }
  return 'localhost';
}

sub _extract_port ($self, $dbh) {
  my $name = $dbh->{Name} // '';
  if ($name =~ /port=(\d+)/i) {
    return int($1);
  }
  return undef;
}

sub _truncate_sql ($self, $sql, $max_length = 100) {
  return undef unless $sql;
  $sql =~ s/\s+/ /g;  # Normalize whitespace
  return length($sql) > $max_length ? substr($sql, 0, $max_length) . '...' : $sql;
}

sub _should_capture_statement ($self) {
  my $client = Sentry::Hub->get_current_hub->client;
  return $client->_options->{send_default_pii} // 0;
}
```

**Enhanced HTTP Client Integrations with Complete Telemetry**:
```perl
# Enhanced lib/Sentry/Integration/LwpUserAgent.pm
package Sentry::Integration::LwpUserAgent;

sub setup_once ($self, $add_global_event_processor, $get_current_hub) {
  return if (!$self->breadcrumbs && !$self->tracing);

  around($self->_package_name, request => sub ($orig, $lwp, $request, @args) {
    my $url = $request->uri;
    
    # Exclude Sentry requests
    return $orig->($lwp, $request, @args) if $request->header('x-sentry-auth');

    my $hub = $get_current_hub->();
    my $span;
    my $start_time = Time::HiRes::time();

    if ($self->tracing && (my $parent_span = $hub->get_scope()->get_span)) {
      $span = $parent_span->start_child({
        op => 'http.client',
        description => $request->method . ' ' . $url->host,
        data => {
          # OpenTelemetry semantic conventions
          'http.request.method' => $request->method,
          'server.address' => $url->host,
          'server.port' => $url->port,
          'url.full' => $url->as_string,
          'url.scheme' => $url->scheme,
          'url.path' => $url->path,
          'http.query' => $url->query,
          'http.request.header.user_agent' => $request->header('user-agent'),
          'http.request.body.size' => length($request->content // ''),
          'thread.id' => threads->tid() // $$,
        },
      });

      # Add trace propagation headers
      $request->header('sentry-trace' => $span->to_trace_parent);
      if (my $baggage = $span->get_baggage()) {
        $request->header('baggage' => $self->_serialize_baggage($baggage));
      }
    }

    my $result = $orig->($lwp, $request, @args);
    my $duration = Time::HiRes::time() - $start_time;

    # Enhanced breadcrumb
    $hub->add_breadcrumb({
      type => 'http',
      category => 'http.client',
      data => {
        'http.request.method' => $request->method,
        'url.full' => $url->as_string,
        'http.response.status_code' => $result->code,
        'http.response_content_length' => length($result->content // ''),
        'duration_ms' => int($duration * 1000),
        'server.address' => $url->host,
      },
      level => $result->is_success ? 'info' : 
               $result->is_client_error ? 'warning' : 'error',
    }) if $self->breadcrumbs;

    if ($span) {
      $span->set_data('http.response.status_code', $result->code);
      $span->set_data('http.response_content_length', length($result->content // ''));
      $span->set_data('duration_ms', int($duration * 1000));
      $span->set_http_status($result->code);
      $span->finish();
    }

    # Capture failed requests if configured
    if ($result->is_error) {
      $self->_maybe_capture_http_error($request, $result, $duration, $span);
    }

    return $result;
  });
}
```

**Enhanced Template Integration**:
```perl
# Enhanced lib/Sentry/Integration/MojoTemplate.pm
package Sentry::Integration::MojoTemplate;

sub setup_once ($self, $add_global_event_processor, $get_current_hub) {
  around('Mojo::Template', render => sub ($orig, $mojo_template, @args) {
    my $hub = $get_current_hub->();
    my $parent_span = $self->tracing && $hub->get_current_scope->get_span;
    my $output;
    
    $hub->with_scope(sub ($scope) {
      my $namespace = $mojo_template->namespace;
      my $span;
      my $start_time = Time::HiRes::time();
      
      if ($parent_span) {
        $span = $parent_span->start_child({
          op => 'template.render',
          description => $mojo_template->name || 'unnamed_template',
          data => {
            'template.engine' => 'mojo',
            'template.name' => $mojo_template->name,
            'template.compiled' => $mojo_template->compiled ? 1 : 0,
            'template.namespace' => $namespace,
            'code.namespace' => $namespace,
            'thread.id' => threads->tid() // $$,
          },
        });
        $scope->set_span($span);
      }

      try {
        $output = $orig->($mojo_template, @args);
        
        my $duration = Time::HiRes::time() - $start_time;
        
        if ($span) {
          $span->set_data('duration_ms', int($duration * 1000));
          $span->set_data('template.output_size', length($output // ''));
        }
        
        if ($self->fix_stacktrace && ref $output && $output->isa('Mojo::Exception')) {
          _fix_template_stack_frames($namespace, $output);
          
          # Capture template rendering error
          Sentry::SDK->capture_exception($output, {
            contexts => {
              template => {
                name => $mojo_template->name,
                namespace => $namespace,
                compiled => $mojo_template->compiled ? 1 : 0,
              }
            },
            tags => {
              template_engine => 'mojo',
              template_error => 1,
            }
          });
        }
      } finally {
        $span->finish() if $span;
      };
    });
    
    return $output;
  });
}
```

**Testing Requirements**:
- Unit tests for integration setup and custom integration handling
- Database integration tests with various DBI drivers
- HTTP client integration tests with different response types
- Template integration tests with error scenarios
- Verify all telemetry data follows OpenTelemetry conventions

#### 1.3 Rate Limiting and Backpressure Management

**Objective**: Implement proper rate limiting to respect Sentry's API limits and prevent abuse.

**New Files**:
- `lib/Sentry/RateLimit.pm`
- `lib/Sentry/Backpressure.pm`

**Implementation Details**:
```perl
package Sentry::RateLimit;

has retry_after => 0;
has rate_limits => sub { {} };  # category => expiry_time

sub is_rate_limited ($self, $category = 'error') {
    my $limit = $self->rate_limits->{$category} // 0;
    return time() < $limit;
}

sub update_from_headers ($self, $headers) {
    # Handle Retry-After header
    if (my $retry = $headers->{'retry-after'}) {
        $self->retry_after(time() + $retry);
    }
    
    # Handle X-Sentry-Rate-Limits header
    if (my $limits = $headers->{'x-sentry-rate-limits'}) {
        $self->_parse_rate_limits($limits);
    }
}
```

**Testing Requirements**:
- Mock HTTP responses with rate limit headers
- Verify proper backoff behavior
- Load testing for backpressure scenarios

#### 1.3 Enhanced Client Options

**Objective**: Add configuration options for new features and improved control.

**Files to Modify**:
- `lib/Sentry/SDK.pm`
- `lib/Sentry/Client.pm`

**New Configuration Options**:
```perl
Sentry::SDK->init({
    # Existing options
    dsn => $dsn,
    release => $release,
    environment => $environment,
    traces_sample_rate => 0.1,
    
    # Integration configuration
    default_integrations => 1,  # Enable built-in integrations
    disabled_integrations => ['DBI', 'MojoTemplate'],  # Disable specific ones
    integrations => [MyCustom::Integration->new()],  # Add custom integrations
    
    # New options
    enable_logs => 0,  # Enable structured logging
    before_send_log => undef,  # Log filtering hook
    max_request_body_size => 'medium',  # none, small, medium, always
    max_attachment_size => 20 * 1024 * 1024,  # 20MB default
    send_default_pii => 0,  # Controls SQL statement capture in DB integration
    capture_failed_requests => 0,
    failed_request_status_codes => [500..599],
    failed_request_targets => ['.*'],
    ignore_errors => [],
    ignore_transactions => [],
    enable_tracing => 1,
    profiles_sample_rate => 0,
    enable_profiling => 0,
    offline_storage_path => undef,
    max_offline_events => 100,
    _experiments => {},
});
```

### Phase 2: Cron Monitoring (Weeks 3-4) ✅ **COMPLETED**

**Priority**: High  
**Dependencies**: Enhanced envelope support  
**Risk**: Medium  
**Status**: ✅ **COMPLETED - All objectives achieved**

#### 2.1 Check-in API Implementation ✅

**Objective**: Enable monitoring of scheduled jobs and cron tasks.

**Implementation Status**: ✅ **COMPLETED**
- Created `lib/Sentry/Crons/CheckIn.pm` with full check-in lifecycle management
- Created `lib/Sentry/Crons/Monitor.pm` with comprehensive monitor configuration
- Created `lib/Sentry/Crons.pm` with high-level API and memory management
- Added `capture_check_in()`, `update_check_in()`, `with_monitor()`, and `upsert_monitor()` to SDK
- Implemented automatic status detection and exception handling
- Added support for environments, contexts, and duration tracking
- All tests passing with comprehensive coverage

**New Files**:
- `lib/Sentry/Crons.pm`
- `lib/Sentry/Crons/CheckIn.pm`
- `lib/Sentry/Crons/Monitor.pm`
- `t/crons.t`
- `examples/phase2_demo.pl`

**API Design**:
```perl
use Sentry::SDK;

# Start monitoring a cron job
my $check_in_id = Sentry::SDK->capture_check_in({
    monitor_slug => 'daily-report-job',
    status => 'in_progress',
    environment => 'production',
});

# Update check-in on completion
Sentry::SDK->update_check_in($check_in_id, 'ok', 30000);

# Helper for wrapping cron jobs
Sentry::SDK->with_monitor('daily-report-job', sub {
    # Your cron job code here
    generate_daily_report();
});
```

#### 2.2 Monitor Configuration ✅

**Objective**: Support for monitor configuration via SDK.

**Implementation Status**: ✅ **COMPLETED**
- Full support for crontab and interval schedules
- Timezone support with validation
- Configurable check-in margins and runtime limits
- Failure and recovery thresholds
- Comprehensive validation with helpful error messages

**Implementation Details**:
```perl
# Monitor configuration
Sentry::SDK->upsert_monitor({
    slug => 'daily-report-job',
    name => 'Daily Report Generation',
    schedule => {
        type => 'crontab',
        value => '0 9 * * *',  # Daily at 9 AM
    },
    checkin_margin => 5,  # minutes
    max_runtime => 30,    # minutes
    timezone => 'UTC',
});
```

**Testing Requirements**: ✅ **COMPLETED**
- Unit tests for check-in and monitor data structures
- Integration tests with SDK methods
- Exception handling and error case testing
- Mock transport for envelope verification

### Phase 3: User Feedback Support (Weeks 5-6)

**Priority**: Medium  
**Dependencies**: Enhanced envelope support  
**Risk**: Low

#### 3.1 User Feedback Collection

**Objective**: Enable collection of user feedback for errors and general issues.

**New Files**:
- `lib/Sentry/UserFeedback.pm`

**API Design**:
```perl
# Capture user feedback associated with an event
Sentry::SDK->capture_user_feedback({
    event_id => $event_id,
    name => 'John Doe',
    email => 'john@example.com',
    comments => 'The page crashed when I clicked submit',
});

# Get the last event ID for feedback forms
my $last_event_id = Sentry::SDK->get_last_event_id();

# Capture standalone feedback (not associated with an error)
Sentry::SDK->capture_user_feedback({
    name => 'Jane Smith',
    email => 'jane@example.com',
    comments => 'Feature request: add dark mode',
    url => 'https://example.com/settings',
    tags => { section => 'ui', priority => 'low' },
});
```

**Implementation Details**:
```perl
package Sentry::UserFeedback;

has event_id => undef;
has name => undef;
has email => undef;
has comments => undef;
has url => undef;
has timestamp => sub { time() };

sub to_envelope_item ($self) {
    return {
        type => 'user_report',
        event_id => $self->event_id,
        name => $self->name,
        email => $self->email,
        comments => $self->comments,
        timestamp => $self->timestamp,
    };
}
```

**Testing Requirements**:
- Unit tests for feedback data structures
- Integration tests with Sentry API
- PII handling verification

### Phase 4: Attachment Support (Weeks 7-8)

**Priority**: Medium  
**Dependencies**: Enhanced envelope support  
**Risk**: Medium

#### 4.1 Attachment Implementation

**Objective**: Support file attachments for events to provide additional context.

**New Files**:
- `lib/Sentry/Attachment.pm`

**API Design**:
```perl
# Add attachment from file path
Sentry::SDK->add_attachment({
    path => '/var/log/application.log',
    filename => 'application.log',
    content_type => 'text/plain',
    add_to_transactions => 0,  # Don't attach to transactions by default
});

# Add attachment from data
Sentry::SDK->add_attachment({
    data => $screenshot_bytes,
    filename => 'error_screenshot.png',
    content_type => 'image/png',
});

# Add attachment with custom scope
Sentry::SDK->configure_scope(sub ($scope) {
    $scope->add_attachment({
        path => '/tmp/debug.json',
        filename => 'debug_data.json',
    });
});
```

**Implementation Details**:
```perl
package Sentry::Attachment;

has filename => undef;
has content_type => undef;
has data => undef;
has path => undef;
has add_to_transactions => 0;

sub read_file ($self) {
    return $self->data if defined $self->data;
    
    die "No file path specified" unless $self->path;
    die "File does not exist: " . $self->path unless -f $self->path;
    
    my $size = -s $self->path;
    my $max_size = Sentry::Hub->get_current_hub->client->_options->{max_attachment_size} // (20 * 1024 * 1024);
    
    die "File too large: $size bytes (max: $max_size)" if $size > $max_size;
    
    return Mojo::File->new($self->path)->slurp;
}

sub to_envelope_item ($self) {
    return {
        type => 'attachment',
        filename => $self->filename,
        content_type => $self->content_type,
        data => $self->read_file,
    };
}
```

**Testing Requirements**:
- File size limit enforcement
- Content type detection
- Binary file handling
- Memory usage optimization

### Phase 5: Enhanced HTTP Client Integration & Distributed Tracing (Weeks 9-10)

**Priority**: High  
**Dependencies**: Enhanced client options  
**Risk**: Low

#### 5.1 Complete Distributed Tracing Support

**Objective**: Enable seamless tracing between frontend JavaScript applications and Perl backend services.

**Files to Modify**:
- `lib/Sentry/Integration/LwpUserAgent.pm`
- `lib/Sentry/Integration/MojoUserAgent.pm`
- `lib/Sentry/Tracing/Span.pm`
- `lib/Sentry/Tracing/Transaction.pm`

**New Files**:
- `lib/Sentry/Tracing/Propagation.pm`
- `lib/Sentry/Tracing/BaggageHeader.pm`

**Enhanced Features for Frontend-Backend Integration**:

```perl
# Configuration for distributed tracing
Sentry::SDK->init({
    capture_failed_requests => 1,
    failed_request_status_codes => [400..499, 500..599],
    failed_request_targets => [
        'https://api.example.com/.*',
        'https://external-service.com/.*',
    ],
    send_default_pii => 0,  # Controls header and body capture
    
    # Distributed tracing configuration
    trace_propagation_targets => [
        'https://api.example.com',
        'https://internal-service.local',
        qr/^https:\/\/.*\.mycompany\.com/,  # Regex support
    ],
    enable_trace_sampling => 1,
});
```

**Complete Trace Propagation Implementation**:

```perl
package Sentry::Tracing::Propagation;

# Extract trace context from incoming HTTP headers
sub extract_trace_context ($package, $headers) {
    my %context;
    
    # Extract sentry-trace header
    if (my $sentry_trace = $headers->{'sentry-trace'}) {
        %context = $package->_parse_sentry_trace($sentry_trace);
    }
    
    # Extract baggage header for dynamic sampling context
    if (my $baggage = $headers->{'baggage'}) {
        $context{baggage} = $package->_parse_baggage($baggage);
    }
    
    return \%context;
}

# Inject trace context into outgoing HTTP headers
sub inject_trace_context ($package, $span, $headers) {
    # Add sentry-trace header
    $headers->{'sentry-trace'} = $span->to_trace_parent();
    
    # Add baggage header for dynamic sampling context
    if (my $baggage = $span->get_baggage()) {
        $headers->{'baggage'} = $package->_serialize_baggage($baggage);
    }
}

# Parse sentry-trace header: trace_id-span_id-sampled
sub _parse_sentry_trace ($package, $header) {
    return {} unless $header;
    
    my ($trace_id, $span_id, $sampled) = split /-/, $header;
    
    return {
        trace_id => $trace_id,
        parent_span_id => $span_id,
        sampled => $sampled eq '1' ? 1 : $sampled eq '0' ? 0 : undef,
    };
}

# Parse baggage header for dynamic sampling context
sub _parse_baggage ($package, $baggage_header) {
    my %baggage;
    
    for my $item (split /,\s*/, $baggage_header) {
        my ($key, $value) = split /=/, $item, 2;
        $baggage{$key} = $value if defined $value;
    }
    
    return \%baggage;
}

# Serialize baggage to header format
sub _serialize_baggage ($package, $baggage) {
    return join ', ', map { "$_=$baggage->{$_}" } keys %$baggage;
}
```

**Enhanced Span Implementation with Baggage Support**:

```perl
# Enhanced Sentry::Tracing::Span
package Sentry::Tracing::Span;

has baggage => sub { {} };

sub to_trace_parent ($self) {
    my $sampled_string = '';
    
    if (defined $self->sampled) {
        $sampled_string = '-' . ($self->sampled ? '1' : '0');
    }
    
    return $self->trace_id . '-' . $self->span_id . $sampled_string;
}

sub get_baggage ($self) {
    my %baggage = $self->baggage->%*;
    
    # Add dynamic sampling context
    my $client = Sentry::Hub->get_current_hub->client;
    if (my $dsn = $client->_dsn) {
        $baggage{'sentry-public_key'} = $dsn->user;
        $baggage{'sentry-trace_id'} = $self->trace_id;
        
        if (my $release = $client->_options->{release}) {
            $baggage{'sentry-release'} = $release;
        }
        
        if (my $environment = $client->_options->{environment}) {
            $baggage{'sentry-environment'} = $environment;
        }
    }
    
    return \%baggage;
}

sub set_baggage_item ($self, $key, $value) {
    $self->baggage->{$key} = $value;
}
```

**Framework Integration for Incoming Requests**:

```perl
# Enhanced Mojolicious integration
package Mojolicious::Plugin::SentrySDK;

sub register ($self, $app, $config) {
    # Existing setup...
    
    # Add hook to extract trace context from incoming requests
    $app->hook(before_dispatch => sub ($c) {
        my $headers = $c->req->headers;
        
        # Extract trace context from incoming request
        my $trace_context = Sentry::Tracing::Propagation->extract_trace_context({
            'sentry-trace' => $headers->header('sentry-trace'),
            'baggage' => $headers->header('baggage'),
        });
        
        # Continue or start a new transaction with the extracted context
        if ($trace_context->{trace_id}) {
            my $transaction = Sentry::SDK->continue_transaction({
                name => $c->req->method . ' ' . $c->req->url->path,
                op => 'http.server',
                trace_id => $trace_context->{trace_id},
                parent_span_id => $trace_context->{parent_span_id},
                sampled => $trace_context->{sampled},
                baggage => $trace_context->{baggage},
            });
        } else {
            my $transaction = Sentry::SDK->start_transaction({
                name => $c->req->method . ' ' . $c->req->url->path,
                op => 'http.server',
            });
        }
        
        # Set transaction in scope
        Sentry::SDK->configure_scope(sub ($scope) {
            $scope->set_span($transaction);
        });
    });
    
    # Add hook to finish transaction after response
    $app->hook(after_render => sub ($c) {
        Sentry::SDK->configure_scope(sub ($scope) {
            if (my $transaction = $scope->get_span) {
                $transaction->set_http_status($c->res->code);
                $transaction->finish();
            }
        });
    });
}
```

**API for Manual Trace Continuation**:

```perl
# Manual trace continuation API
use Sentry::SDK;

# In your Perl backend, extract trace from frontend request
sub handle_api_request ($request) {
    my $sentry_trace = $request->header('sentry-trace');
    my $baggage = $request->header('baggage');
    
    # Continue the trace started by frontend
    my $transaction = Sentry::SDK->continue_transaction({
        name => 'api.process_data',
        op => 'http.server',
        headers => {
            'sentry-trace' => $sentry_trace,
            'baggage' => $baggage,
        },
    });
    
    Sentry::SDK->configure_scope(sub ($scope) {
        $scope->set_span($transaction);
        
        # Add backend-specific context
        $scope->set_tag('service', 'backend-api');
        $scope->set_context('api_request', {
            endpoint => '/api/process_data',
            user_id => $request->param('user_id'),
        });
    });
    
    # Your business logic here
    my $result = process_business_logic();
    
    # Add custom spans for database operations
    my $db_span = $transaction->start_child({
        op => 'db.query',
        description => 'SELECT * FROM users WHERE id = ?',
    });
    
    my $user = get_user_from_db($request->param('user_id'));
    $db_span->finish();
    
    # Finish the transaction
    $transaction->set_http_status(200);
    $transaction->finish();
    
    return $result;
}

# For outgoing requests to other services
sub call_external_service ($data) {
    my $span = Sentry::SDK->get_current_span();
    
    # Create child span for external service call
    my $external_span = $span->start_child({
        op => 'http.client',
        description => 'POST https://external-api.com/process',
    });
    
    # The HTTP client integration will automatically add trace headers
    my $response = $http_client->post('https://external-api.com/process', 
        json => $data
    );
    
    $external_span->set_http_status($response->code);
    $external_span->finish();
    
    return $response;
}
```

**Frontend Integration Example**:

For complete frontend-backend tracing, your frontend would look like this:

```javascript
import * as Sentry from "@sentry/browser";

Sentry.init({
  dsn: "YOUR_DSN",
  integrations: [
    new Sentry.BrowserTracing({
      tracePropagationTargets: [
        "localhost",
        "https://api.example.com",
        /^https:\/\/api\.mycompany\.com/,
      ],
    }),
  ],
  tracesSampleRate: 0.1,
});

// Frontend API call - trace headers automatically added
async function callBackendAPI() {
  const transaction = Sentry.startTransaction({
    name: "user-action",
    op: "navigation",
  });
  
  Sentry.getCurrentHub().configureScope(scope => {
    scope.setSpan(transaction);
  });
  
  try {
    // This request will include sentry-trace and baggage headers
    const response = await fetch('/api/process_data', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ user_id: 123 })
    });
    
    const data = await response.json();
    transaction.setStatus('ok');
    return data;
  } catch (error) {
    transaction.setStatus('internal_error');
    Sentry.captureException(error);
    throw error;
  } finally {
    transaction.finish();
  }
}
```

#### 5.2 Enhanced HTTP Client Error Capture

**Enhanced HTTP Monitoring**:
```perl
# Enhanced LWP integration with failed request capture
package Sentry::Integration::LwpUserAgent;

sub _capture_http_error ($self, $request, $response, $start_time, $span) {
    my $client = Sentry::Hub->get_current_hub->client;
    return unless $client->_options->{capture_failed_requests};
    
    my $status = $response->code;
    return unless $self->_should_capture_status($status);
    
    my $url = $request->uri->as_string;
    return unless $self->_should_capture_url($url);
    
    my $duration = (time() - $start_time) * 1000;  # milliseconds
    
    Sentry::SDK->capture_exception(
        "HTTP Client Error: $status " . $response->message,
        {
            contexts => {
                request => {
                    url => $url,
                    method => $request->method,
                    headers => $self->_filter_headers($request->headers),
                },
                response => {
                    status_code => $status,
                    headers => $self->_filter_headers($response->headers),
                    body_size => length($response->content),
                },
                trace => {
                    trace_id => $span ? $span->trace_id : undef,
                    span_id => $span ? $span->span_id : undef,
                }
            },
            extra => {
                duration_ms => $duration,
            },
            fingerprint => ['http-client', $request->method, $status],
        }
    );
}
```

**Testing Requirements**:
- Cross-service trace continuity verification
- Baggage header propagation tests
- Frontend-backend integration tests
- Header filtering and PII protection
- Performance impact assessment
- URL pattern matching for trace propagation targets

This enhanced distributed tracing support will enable complete observability across your frontend and backend services, allowing you to trace user requests from the browser through your Perl backend and any external services you call.

### Phase 6: Profiling Support (Weeks 11-12)

**Priority**: Medium  
**Dependencies**: Enhanced envelope support  
**Risk**: High

#### 6.1 Continuous Profiling

**Objective**: Add profiling capabilities for performance analysis.

**New Files**:
- `lib/Sentry/Profiling.pm`
- `lib/Sentry/Profiling/Profile.pm`
- `lib/Sentry/Profiling/Sampler.pm`

**API Design**:
```perl
# Enable profiling in configuration
Sentry::SDK->init({
    enable_profiling => 1,
    profiles_sample_rate => 0.1,  # 10% of transactions
});

# Manual profiling
my $profiler = Sentry::SDK->start_profiler({
    name => 'expensive-operation',
});

expensive_operation();

$profiler->finish();

# Automatic profiling with transactions
my $transaction = Sentry::SDK->start_transaction({
    name => 'process_data',
    op => 'task',
});

# Profiling automatically enabled if configured
process_large_dataset();

$transaction->finish();
```

**Implementation Details**:
```perl
package Sentry::Profiling::Profile;

has start_time => sub { Time::HiRes::time() };
has end_time => undef;
has samples => sub { [] };
has frames => sub { {} };

sub add_sample ($self, $stack_trace, $timestamp = undef) {
    $timestamp //= Time::HiRes::time();
    
    my $frame_ids = [];
    for my $frame (@$stack_trace) {
        my $frame_id = $self->_get_or_create_frame($frame);
        push @$frame_ids, $frame_id;
    }
    
    push $self->samples->@*, {
        stack_id => join(':', @$frame_ids),
        timestamp => $timestamp,
    };
}

sub to_envelope_item ($self) {
    return {
        type => 'profile',
        profile => {
            frames => $self->frames,
            samples => $self->samples,
            start_ns => int($self->start_time * 1_000_000_000),
            end_ns => int($self->end_time * 1_000_000_000),
        },
    };
}
```

**Testing Requirements**:
- Profiling overhead measurement
- Stack trace collection accuracy
- Memory usage optimization
- Cross-platform compatibility

### Phase 6: Structured Logging Support (Weeks 11-12)

**Priority**: High  
**Dependencies**: Enhanced envelope support  
**Risk**: Medium

#### 6.1 Sentry Logging API

**Objective**: Implement Sentry's new structured logging feature for comprehensive log collection and analysis.

**New Files**:
- `lib/Sentry/Logger.pm`
- `lib/Sentry/Logger/LogRecord.pm`
- `lib/Sentry/Logger/Buffer.pm`

**API Design**:
```perl
use Sentry::SDK;

# Enable logging in configuration
Sentry::SDK->init({
    enable_logs => 1,
    before_send_log => sub ($log) {
        # Filter or modify log before sending
        return $log unless $log->{level} eq 'debug';
        return undef;  # Skip debug logs in production
    },
});

# Access the logger
my $logger = Sentry::SDK->logger;

# Basic logging methods
$logger->trace('Detailed trace information');
$logger->debug('Debug information for developers');
$logger->info('General information about program execution');
$logger->warn('Warning about potential issues');
$logger->error('Error that occurred but app can continue');
$logger->fatal('Critical error that may cause app to crash');

# Structured logging with parameters
$logger->info('User %s logged in from %s', $user_id, $ip_address);
$logger->warn('API call to %s took %d ms (threshold: %d ms)', 
              $endpoint, $duration, $threshold);

# Logging with additional attributes
$logger->error('Database connection failed', {
    attributes => {
        'db.host' => 'db.example.com',
        'db.port' => 5432,
        'retry_count' => 3,
        'connection_timeout' => 30,
    }
});

# Template-based logging for structured data
$logger->info(
    'Processing order {order_id} for user {user_id}',
    order_id => $order->id,
    user_id => $user->id,
    attributes => {
        'order.total' => $order->total,
        'order.items_count' => scalar(@{$order->items}),
    }
);
```

**Implementation Details**:
```perl
package Sentry::Logger;
use Mojo::Base -base, -signatures;

use Sentry::Logger::LogRecord;
use Sentry::Logger::Buffer;
use Time::HiRes 'time';

has buffer => sub { Sentry::Logger::Buffer->new };
has enabled => sub ($self) { 
    Sentry::Hub->get_current_hub->client->_options->{enable_logs} // 0 
};

# Log level methods
sub trace ($self, $message, @params) { $self->_log('trace', 1, $message, @params) }
sub debug ($self, $message, @params) { $self->_log('debug', 5, $message, @params) }
sub info  ($self, $message, @params) { $self->_log('info', 9, $message, @params) }
sub warn  ($self, $message, @params) { $self->_log('warn', 13, $message, @params) }
sub error ($self, $message, @params) { $self->_log('error', 17, $message, @params) }
sub fatal ($self, $message, @params) { $self->_log('fatal', 21, $message, @params) }

sub _log ($self, $level, $severity_number, $message, @params) {
    return unless $self->enabled;
    
    my ($template_params, $attributes) = $self->_parse_params(@params);
    
    my $log_record = Sentry::Logger::LogRecord->new(
        timestamp => time(),
        level => $level,
        severity_number => $severity_number,
        body => $self->_format_message($message, $template_params),
        trace_id => $self->_get_current_trace_id(),
        attributes => $self->_build_attributes($message, $template_params, $attributes),
    );
    
    # Apply before_send_log hook
    my $client = Sentry::Hub->get_current_hub->client;
    if (my $hook = $client->_options->{before_send_log}) {
        $log_record = $hook->($log_record->to_hash);
        return unless $log_record;  # Hook can filter out logs
    }
    
    $self->buffer->add($log_record);
}

sub _build_attributes ($self, $template, $params, $extra_attributes) {
    my $hub = Sentry::Hub->get_current_hub;
    my $client = $hub->client;
    my $scope = $hub->scope;
    
    my %attributes = (
        # Required Sentry attributes
        'sentry.sdk.name' => { value => 'sentry.perl', type => 'string' },
        'sentry.sdk.version' => { value => $Sentry::SDK::VERSION->stringify, type => 'string' },
    );
    
    # Optional Sentry attributes
    if (my $env = $client->_options->{environment}) {
        $attributes{'sentry.environment'} = { value => $env, type => 'string' };
    }
    
    if (my $release = $client->_options->{release}) {
        $attributes{'sentry.release'} = { value => $release, type => 'string' };
    }
    
    # Trace context
    if (my $span = $scope->span) {
        $attributes{'sentry.trace.parent_span_id'} = { 
            value => $span->span_id, 
            type => 'string' 
        };
    }
    
    # Template and parameters for structured logging
    if (@$params > 0) {
        $attributes{'sentry.message.template'} = { value => $template, type => 'string' };
        for my $i (0 .. $#$params) {
            my $param = $params->[$i];
            my $type = $self->_detect_type($param);
            $attributes{"sentry.message.parameter.$i"} = { 
                value => $param, 
                type => $type 
            };
        }
    }
    
    # User-provided attributes
    if ($extra_attributes) {
        for my $key (keys %$extra_attributes) {
            my $value = $extra_attributes->{$key};
            my $type = $self->_detect_type($value);
            $attributes{$key} = { value => $value, type => $type };
        }
    }
    
    return \%attributes;
}

sub _detect_type ($self, $value) {
    return 'boolean' if JSON::PP::is_bool($value);
    return 'integer' if $value =~ /^-?\d+$/;
    return 'double' if $value =~ /^-?\d+\.\d+$/;
    return 'string';
}
```

**Log Record Structure**:
```perl
package Sentry::Logger::LogRecord;

has timestamp => sub { time() };
has trace_id => undef;
has level => undef;          # trace, debug, info, warn, error, fatal
has severity_number => undef; # 1-4, 5-8, 9-12, 13-16, 17-20, 21-24
has body => undef;           # The formatted log message
has attributes => sub { {} }; # Key-value pairs with types

sub to_hash ($self) {
    return {
        timestamp => $self->timestamp,
        trace_id => $self->trace_id,
        level => $self->level,
        severity_number => $self->severity_number,
        body => $self->body,
        attributes => $self->attributes,
    };
}

sub to_envelope_item ($self) {
    return {
        type => 'log',
        item_count => 1,
        content_type => 'application/vnd.sentry.items.log+json',
    };
}
```

**Buffering and Batching**:
```perl
package Sentry::Logger::Buffer;

has logs => sub { [] };
has max_buffer_size => 100;
has flush_interval => 5; # seconds
has last_flush => sub { time() };

sub add ($self, $log_record) {
    push $self->logs->@*, $log_record;
    
    if (@{$self->logs} >= $self->max_buffer_size || 
        time() - $self->last_flush >= $self->flush_interval) {
        $self->flush();
    }
}

sub flush ($self) {
    return unless @{$self->logs};
    
    my $envelope = Sentry::Envelope->new();
    $envelope->add_item('log', {
        items => [map { $_->to_hash } $self->logs->@*]
    });
    
    # Send via transport
    my $client = Sentry::Hub->get_current_hub->client;
    $client->_transport->send($envelope->serialize());
    
    $self->logs([]);
    $self->last_flush(time());
}
```

**Integration with Existing Perl Logging**:
```perl
# Optional integration with Log::Log4perl
package Sentry::Integration::Log4perl;

sub setup {
    my $appender = Log::Log4perl::Appender->new(
        'Sentry::Appender::Log4perl',
        name => 'sentry',
    );
    
    # Configure to send logs to Sentry
    Log::Log4perl->get_logger()->add_appender($appender);
}

# Optional integration with Mojo::Log
package Sentry::Integration::MojoLog;

sub setup ($self) {
    my $app = Mojo::IOLoop->singleton->app;
    return unless $app && $app->can('log');
    
    my $original_log = $app->log->can('log');
    
    Mojo::Util::monkey_patch('Mojo::Log', log => sub {
        my ($log, $level, @messages) = @_;
        
        # Send to Sentry if logging is enabled
        if (Sentry::SDK->logger->enabled) {
            for my $message (@messages) {
                Sentry::SDK->logger->can($level)->($message);
            }
        }
        
        # Call original log method
        return $original_log->($log, $level, @messages);
    });
}
```

**Testing Requirements**:
- Unit tests for log record creation and formatting
- Buffer flushing behavior verification
- Structured logging parameter handling
- Integration tests with various log levels
- Performance impact assessment for high-volume logging

### Phase 7: Profiling Support (Weeks 13-14)

**Priority**: Medium  
**Dependencies**: Enhanced envelope support  
**Risk**: High

#### 7.1 Continuous Profiling

**Objective**: Add profiling capabilities for performance analysis.

**New Files**:
- `lib/Sentry/Profiling.pm`
- `lib/Sentry/Profiling/Profile.pm`
- `lib/Sentry/Profiling/Sampler.pm`

**API Design**:
```perl
# Enable profiling in configuration
Sentry::SDK->init({
    enable_profiling => 1,
    profiles_sample_rate => 0.1,  # 10% of transactions
});

# Manual profiling
my $profiler = Sentry::SDK->start_profiler({
    name => 'expensive-operation',
});

expensive_operation();

$profiler->finish();

# Automatic profiling with transactions
my $transaction = Sentry::SDK->start_transaction({
    name => 'process_data',
    op => 'task',
});

# Profiling automatically enabled if configured
process_large_dataset();

$transaction->finish();
```

### Phase 8: Advanced Features (Weeks 15-16)

**Priority**: Low  
**Dependencies**: All previous phases  
**Risk**: Medium

#### 8.1 Offline Caching

**Objective**: Store events locally when network is unavailable.

**New Files**:
- `lib/Sentry/Cache/Offline.pm`
- `lib/Sentry/Transport/CachedHttp.pm`

#### 8.2 Feature Flag Tracking

**API Design**:
```perl
Sentry::SDK->add_feature_flag('new-checkout-flow', 1);
Sentry::SDK->add_feature_flag('payment-provider', 'stripe');
```

#### 8.3 Minion Job Queue Integration

**Objective**: Add comprehensive telemetry support for Mojolicious Minion job queue system.

**New Files**:
- `lib/Sentry/Integration/Minion.pm`

**Enhanced Files**:
- `lib/Mojolicious/Plugin/SentrySDK.pm`

**API Design & Implementation**:

```perl
# Enhanced Mojolicious::Plugin::SentrySDK with Minion support
package Mojolicious::Plugin::SentrySDK;

sub register ($self, $app, $conf) {
  # Existing HTTP monitoring setup...
  
  # Add Minion integration if available
  if ($app->can('minion') && $app->minion) {
    $self->_setup_minion_monitoring($app, $conf);
  }
}

sub _setup_minion_monitoring ($self, $app, $conf) {
  my $minion = $app->minion;
  
  # Hook into job lifecycle
  $minion->on(job => sub ($minion, $job) {
    my $job_id = $job->id;
    my $task = $job->task;
    my $args = $job->args;
    my $queue = $job->info->{queue} // 'default';
    
    # Start job transaction
    my $transaction = Sentry::SDK->start_transaction({
      name => "minion.job.$task",
      op => 'queue.job',
      data => {
        'job.id' => $job_id,
        'job.task' => $task,
        'job.queue' => $queue,
        'job.attempts' => $job->info->{attempts} // 0,
        'job.retries' => $job->info->{retries} // 0,
        'job.priority' => $job->info->{priority} // 0,
        'job.created' => $job->info->{created},
        'job.delayed' => $job->info->{delayed},
        'thread.id' => $$,
        'worker.id' => $job->info->{worker} // 'unknown',
      },
    });
    
    Sentry::SDK->configure_scope(sub ($scope) {
      $scope->set_span($transaction);
      $scope->set_tag('job_queue', 'minion');
      $scope->set_tag('job_task', $task);
      $scope->set_tag('job_queue_name', $queue);
      
      $scope->set_context('job', {
        id => $job_id,
        task => $task,
        queue => $queue,
        args => $conf->{capture_job_args} ? $args : '[hidden]',
        attempts => $job->info->{attempts} // 0,
        retries => $job->info->{retries} // 0,
        priority => $job->info->{priority} // 0,
      });
    });
    
    # Monitor job execution
    my $start_time = Time::HiRes::time();
    
    $job->on(finished => sub ($job, $result) {
      my $duration = Time::HiRes::time() - $start_time;
      
      $transaction->set_data('job.duration_ms', int($duration * 1000));
      $transaction->set_data('job.result_size', length(ref($result) ? encode_json($result) : ($result // '')));
      $transaction->set_status('ok');
      
      # Add job success breadcrumb
      Sentry::SDK->add_breadcrumb({
        type => 'default',
        category => 'job.success',
        message => "Job $task completed successfully",
        level => 'info',
        data => {
          'job.id' => $job_id,
          'job.task' => $task,
          'job.queue' => $queue,
          'job.duration_ms' => int($duration * 1000),
        },
      });
      
      $transaction->finish();
    });
    
    $job->on(failed => sub ($job, $error) {
      my $duration = Time::HiRes::time() - $start_time;
      
      $transaction->set_data('job.duration_ms', int($duration * 1000));
      $transaction->set_data('job.error', "$error");
      $transaction->set_status('internal_error');
      
      # Capture job failure as exception
      Sentry::SDK->capture_exception($error, {
        contexts => {
          job => {
            id => $job_id,
            task => $task,
            queue => $queue,
            args => $conf->{capture_job_args} ? $args : '[hidden]',
            attempts => $job->info->{attempts} // 0,
            worker => $job->info->{worker},
          }
        },
        tags => {
          job_queue => 'minion',
          job_task => $task,
          job_failure => 1,
        },
        fingerprint => ['job-failure', $task, $queue],
      });
      
      # Add job failure breadcrumb
      Sentry::SDK->add_breadcrumb({
        type => 'error',
        category => 'job.failure',
        message => "Job $task failed: $error",
        level => 'error',
        data => {
          'job.id' => $job_id,
          'job.task' => $task,
          'job.queue' => $queue,
          'job.duration_ms' => int($duration * 1000),
          'job.error' => "$error",
        },
      });
      
      $transaction->finish();
    });
  });
  
  # Monitor worker lifecycle
  $minion->on(worker => sub ($minion, $worker) {
    my $worker_id = $worker->id;
    
    Sentry::SDK->configure_scope(sub ($scope) {
      $scope->set_tag('minion_worker_id', $worker_id);
      $scope->set_context('worker', {
        id => $worker_id,
        pid => $$,
        host => $worker->info->{host},
        started => $worker->info->{started},
      });
    });
    
    # Track worker start
    Sentry::SDK->add_breadcrumb({
      type => 'default',
      category => 'worker.start',
      message => "Minion worker $worker_id started",
      level => 'info',
      data => {
        'worker.id' => $worker_id,
        'worker.pid' => $$,
        'worker.host' => $worker->info->{host},
      },
    });
  });
}
```

**Dedicated Minion Integration**:

```perl
package Sentry::Integration::Minion;
use Mojo::Base 'Sentry::Integration::Base', -signatures;

has name => 'Minion';
has capture_job_args => 0;
has capture_job_results => 0;
has track_job_performance => 1;

sub setup_once ($self, $add_global_event_processor, $get_current_hub) {
  # This integration is automatically set up by the Mojolicious plugin
  # when Minion is detected, but can also be used standalone
  
  return unless eval { require Minion; 1 };
  
  # Add global event processor to enrich events with job context
  $add_global_event_processor->(sub ($event, $hint) {
    my $hub = $get_current_hub->();
    my $scope = $hub->get_scope();
    
    # Add job context to all events if we're in a job
    if (my $job_context = $scope->get_context('job')) {
      $event->{contexts}{job} = $job_context;
      $event->{tags}{job_task} //= $job_context->{task};
      $event->{tags}{job_queue} //= $job_context->{queue};
    }
    
    return $event;
  });
}

# Helper methods for manual job monitoring
sub capture_job_start ($package, $job_id, $task, %options) {
  my $transaction = Sentry::SDK->start_transaction({
    name => "minion.job.$task",
    op => 'queue.job',
    data => {
      'job.id' => $job_id,
      'job.task' => $task,
      %options,
    },
  });
  
  Sentry::SDK->configure_scope(sub ($scope) {
    $scope->set_span($transaction);
    $scope->set_tag('job_queue', 'minion');
    $scope->set_tag('job_task', $task);
  });
  
  return $transaction;
}

sub capture_job_finish ($package, $transaction, $status, %data) {
  $transaction->set_data($_, $data{$_}) for keys %data;
  $transaction->set_status($status);
  $transaction->finish();
}
```

**Usage Examples**:

```perl
# 1. Automatic monitoring (via Mojolicious plugin)
use Mojolicious::Lite -signatures;

plugin 'SentrySDK' => {
  dsn => $ENV{SENTRY_DSN},
  capture_job_args => 1,  # Capture job arguments (be careful with PII)
  capture_job_results => 0,  # Don't capture results by default
};

plugin 'Minion' => { SQLite => ':temp:' };

# Define a job - automatically monitored
app->minion->add_task(send_email => sub ($job, $to, $subject, $body) {
  # Job execution is automatically wrapped in Sentry transaction
  # Any exceptions are automatically captured
  
  my $mail = send_mail($to, $subject, $body);
  
  # Add custom job metadata
  Sentry::SDK->configure_scope(sub ($scope) {
    $scope->set_tag('email_provider', 'sendgrid');
    $scope->set_context('email', {
      to => $to,
      subject => $subject,
      message_id => $mail->message_id,
    });
  });
  
  return { message_id => $mail->message_id };
});

# 2. Manual monitoring for custom job systems
use Sentry::Integration::Minion;

sub process_custom_job ($job_data) {
  my $transaction = Sentry::Integration::Minion->capture_job_start(
    $job_data->{id},
    $job_data->{task},
    'job.queue' => $job_data->{queue},
    'job.priority' => $job_data->{priority},
  );
  
  try {
    my $result = execute_job_logic($job_data);
    
    Sentry::Integration::Minion->capture_job_finish(
      $transaction,
      'ok',
      'job.result_size' => length(encode_json($result)),
      'job.records_processed' => $result->{count},
    );
    
    return $result;
  } catch {
    Sentry::SDK->capture_exception($_);
    
    Sentry::Integration::Minion->capture_job_finish(
      $transaction,
      'internal_error',
      'job.error' => "$_",
    );
    
    die $_;
  };
}

# 3. Job queue monitoring and alerting
app->minion->add_task(monitor_queue_health => sub ($job) {
  my $stats = app->minion->stats;
  
  # Monitor queue depth
  if ($stats->{active_jobs} > 1000) {
    Sentry::SDK->capture_message(
      "High job queue depth: " . $stats->{active_jobs} . " active jobs",
      'warning',
      {
        extra => {
          queue_stats => $stats,
        },
        tags => {
          alert_type => 'queue_depth',
          severity => 'high',
        },
      }
    );
  }
  
  # Monitor failed jobs
  if ($stats->{failed_jobs} > $stats->{finished_jobs} * 0.1) {
    Sentry::SDK->capture_message(
      "High job failure rate: " . $stats->{failed_jobs} . " failed jobs",
      'error',
      {
        extra => {
          queue_stats => $stats,
          failure_rate => $stats->{failed_jobs} / ($stats->{finished_jobs} || 1),
        },
        tags => {
          alert_type => 'failure_rate',
          severity => 'critical',
        },
      }
    );
  }
});
```

**Performance Monitoring Features**:

- **Job Execution Time**: Track how long jobs take to complete
- **Queue Depth Monitoring**: Alert on high queue backlogs
- **Job Failure Rates**: Monitor and alert on job failure patterns
- **Worker Performance**: Track worker efficiency and resource usage
- **Queue-specific Metrics**: Monitor different queues separately
- **Job Retry Patterns**: Track jobs that require multiple attempts

**Configuration Options**:

```perl
plugin 'SentrySDK' => {
  dsn => $ENV{SENTRY_DSN},
  
  # Minion-specific options
  capture_job_args => 0,       # Capture job arguments (PII consideration)
  capture_job_results => 0,    # Capture job return values
  track_job_performance => 1,   # Enable performance monitoring
  job_sample_rate => 1.0,      # Sample rate for job transactions
  
  # Job filtering
  ignore_job_tasks => ['cleanup', 'heartbeat'],  # Skip monitoring these tasks
  capture_job_tasks => ['important_task'],       # Only monitor these tasks
};
```

**Testing Requirements**:
- Unit tests for job lifecycle monitoring
- Integration tests with actual Minion jobs
- Performance impact assessment
- Queue depth and failure rate monitoring tests
- Worker lifecycle event testing

This Minion integration provides comprehensive job queue observability including job execution tracing, error capture, performance monitoring, and queue health metrics.

---

## Additional Code Quality Improvements and Refactoring Opportunities

Beyond the feature modernization, several architectural and code quality improvements should be implemented:

### 9.1 Memory Management and Resource Cleanup

**Issues Identified**:
- No explicit cleanup of monkey-patched methods in `Sentry::Util::around()`
- Potential memory leaks from retained closures in integrations
- Global singleton pattern in `Sentry::Hub` without proper cleanup

**Improvements**:

```perl
# Enhanced lib/Sentry/Util.pm with proper cleanup
package Sentry::Util;

my %Patched = ();
my %OriginalRefs = ();  # Store original method references

sub around ($package, $method, $cb) {
  my $key = $package . '::' . $method;
  return if $Patched{$key};

  if (my $e = load_class $package) {
    die ref $e ? "Exception: $e" : "Module $package not found";
  }

  my $orig = $package->can($method);
  $OriginalRefs{$key} = $orig;  # Keep strong reference

  # Use weaker closure to prevent memory leaks
  monkey_patch $package, $method => sub { 
    my $orig_ref = $OriginalRefs{$key};
    $cb->($orig_ref, @_) 
  };

  $Patched{$key} = 1;
  return;
}

# Global cleanup for testing/shutdown
sub cleanup_all_patches {
  for my $key (keys %Patched) {
    my ($package, $method) = split '::', $key, 2;
    restore_original($package, $method);
  }
  %Patched = ();
  %OriginalRefs = ();
}

# Enhanced Hub with proper cleanup
package Sentry::Hub;

sub cleanup ($self) {
  # Clear scope chain
  $self->scopes([]);
  
  # Cleanup client integrations
  if (my $client = $self->client) {
    $client->cleanup_integrations() if $client->can('cleanup_integrations');
  }
  
  # Clear singleton if this is the instance
  $Instance = undef if $Instance && $Instance == $self;
}

# Add DESTROY for automatic cleanup
sub DESTROY ($self) {
  $self->cleanup();
}
```

### 9.2 Error Handling and Resilience Improvements

**Issues Identified**:
- Inconsistent error handling across integrations
- Missing fallback mechanisms for integration failures
- No circuit breaker pattern for failing transports

**Improvements**:

```perl
# Enhanced integration base class
package Sentry::Integration::Base;

has enabled => 1;
has _failed_count => 0;
has _last_failure => 0;
has circuit_breaker_threshold => 5;
has circuit_breaker_timeout => 300;  # 5 minutes

sub is_circuit_open ($self) {
  return 0 unless $self->_failed_count >= $self->circuit_breaker_threshold;
  return (time() - $self->_last_failure) < $self->circuit_breaker_timeout;
}

sub record_failure ($self) {
  $self->_failed_count($self->_failed_count + 1);
  $self->_last_failure(time());
}

sub record_success ($self) {
  $self->_failed_count(0);
}

sub safe_execute ($self, $code) {
  return unless $self->enabled;
  return if $self->is_circuit_open;
  
  try {
    my $result = $code->();
    $self->record_success();
    return $result;
  } catch {
    $self->record_failure();
    warn "Integration " . $self->name . " failed: $_" if $ENV{SENTRY_DEBUG};
    return;
  };
}
```

### 9.3 Performance Optimizations

**Issues Identified**:
- String operations in hot paths (SQL truncation)
- Redundant JSON encoding/decoding
- Inefficient breadcrumb management

**Improvements**:

```perl
# Optimized SQL truncation with caching
package Sentry::Integration::DBI;

has _sql_cache => sub { {} };
has max_cache_size => 1000;

sub _truncate_sql ($self, $sql, $max_length = 100) {
  return $sql if length($sql) <= $max_length;
  
  # Use cache for frequently seen SQL patterns
  my $cache_key = substr($sql, 0, 50);
  my $cache = $self->_sql_cache;
  
  if (exists $cache->{$cache_key}) {
    return $cache->{$cache_key};
  }
  
  # Clean cache if too large
  if (keys %$cache > $self->max_cache_size) {
    %$cache = ();
  }
  
  my $truncated = substr($sql, 0, $max_length) . '...';
  $cache->{$cache_key} = $truncated;
  
  return $truncated;
}

# Optimized breadcrumb management
package Sentry::Hub::Scope;

sub add_breadcrumb ($self, $breadcrumb) {
  $breadcrumb->{timestamp} //= int(time() * 1000);  # Use integer timestamps
  
  my $breadcrumbs = $self->breadcrumbs;
  push @$breadcrumbs, $breadcrumb;
  
  # Efficient sliding window
  my $max_crumbs = $ENV{SENTRY_MAX_BREADCRUMBS} || 100;
  if (@$breadcrumbs > $max_crumbs) {
    splice @$breadcrumbs, 0, @$breadcrumbs - $max_crumbs;
  }
}
```

### 9.4 Type Safety and Validation Improvements

**Issues Identified**:
- No parameter validation in public APIs
- Inconsistent data structure expectations
- Missing input sanitization

**Improvements**:

```perl
# Enhanced parameter validation
package Sentry::SDK;

use Params::ValidationCompiler qw(validation_for);
use Types::Standard qw(Str HashRef ArrayRef Optional);

my $capture_message_validator = validation_for(
  params => {
    message => { type => Str },
    level => { type => Str, optional => 1 },
    capture_context => { type => HashRef, optional => 1 },
  }
);

sub capture_message ($self, @args) {
  my %params = $capture_message_validator->(@args);
  
  _call_on_hub('capture_message', $params{message}, $params{level}, {
    capture_context => $params{capture_context},
  });
}
```

### 9.5 Observability and Debugging Enhancements

**Issues Identified**:
- Limited internal metrics and monitoring
- Difficult to debug SDK behavior in production
- No SDK health reporting

**Improvements**:

```perl
# Internal metrics collection
package Sentry::SDK::Metrics;

has _counters => sub { {} };
has _timers => sub { {} };

sub increment ($self, $metric, $value = 1, $tags = {}) {
  my $key = $self->_metric_key($metric, $tags);
  $self->_counters->{$key} += $value;
}

sub get_metrics ($self) {
  return {
    counters => { %{$self->_counters} },
    timers => { %{$self->_timers} },
    timestamp => time(),
  };
}

# Enhanced SDK with metrics
package Sentry::SDK;

our $METRICS = Sentry::SDK::Metrics->new();

sub capture_exception ($self, @args) {
  my $start = Time::HiRes::time();
  
  $METRICS->increment('sdk.capture_exception.attempts');
  
  try {
    my $result = _call_on_hub('capture_exception', @args);
    $METRICS->increment('sdk.capture_exception.success');
    return $result;
  } catch {
    $METRICS->increment('sdk.capture_exception.errors');
    die $_;
  } finally {
    my $duration = (Time::HiRes::time() - $start) * 1000;
    $METRICS->timing('sdk.capture_exception.duration', $duration);
  };
}
```

### 9.6 Configuration Management Improvements

**Issues Identified**:
- Environment variable handling spread across multiple files
- No configuration validation
- Missing configuration schema documentation

**Improvements**:

```perl
# Centralized configuration management
package Sentry::Config;

use Types::Standard qw(Str Num Bool HashRef ArrayRef Optional);

my $CONFIG_SCHEMA = {
  dsn => { type => Str, env => 'SENTRY_DSN' },
  debug => { type => Bool, env => 'SENTRY_DEBUG', default => 0 },
  traces_sample_rate => { 
    type => Num, 
    env => 'SENTRY_TRACES_SAMPLE_RATE', 
    default => 0,
    validator => sub { $_[0] >= 0 && $_[0] <= 1 },
  },
  max_breadcrumbs => {
    type => Num,
    env => 'SENTRY_MAX_BREADCRUMBS',
    default => 100,
    validator => sub { $_[0] > 0 && $_[0] <= 1000 },
  },
};

sub load_config ($package, $user_options = {}) {
  my $config = {};
  
  for my $key (keys %$CONFIG_SCHEMA) {
    my $schema = $CONFIG_SCHEMA->{$key};
    
    # Priority: user_options > environment > default
    my $value = $user_options->{$key} 
      // ($schema->{env} ? $ENV{$schema->{env}} : undef)
      // $schema->{default};
    
    $config->{$key} = $value;
  }
  
  return $config;
}
```

These refactoring improvements focus on production readiness, maintainability, and developer experience. They address:

1. **Memory Management**: Proper cleanup to prevent leaks in long-running applications
2. **Error Resilience**: Circuit breaker patterns and graceful degradation
3. **Performance**: Optimizations for hot paths and resource usage
4. **Type Safety**: Parameter validation and data sanitization  
5. **Observability**: Internal metrics and health reporting for SDK monitoring
6. **Configuration**: Centralized, validated configuration management

---

## Testing Strategy

### Unit Testing
- **Coverage Target**: 90% code coverage for all new features
- **Framework**: Test::Spec (current framework)
- **Mock Objects**: Extend existing Mock::* infrastructure
- **Snapshot Testing**: Use Test::Snapshot for envelope serialization

### Integration Testing
- **Sentry Backend**: Tests against real Sentry instance
- **Mock Server**: Local HTTP server for controlled testing
- **Framework Tests**: Verify integrations with Mojolicious, CGI::Application
- **Performance Tests**: Measure overhead of new features

### Backward Compatibility Testing
- **API Compatibility**: Ensure all existing APIs continue to work
- **Configuration Compatibility**: Support legacy configuration options
- **Version Migration**: Test upgrades from previous versions

### Performance Testing
- **Benchmark Suite**: Performance impact measurement
- **Memory Usage**: Monitor memory consumption
- **Startup Time**: SDK initialization overhead
- **Runtime Overhead**: Impact on application performance

## Migration Guide

### Upgrading from 1.3.x

1. **No Breaking Changes**: All existing code will continue to work
2. **New Dependencies**: May require additional CPAN modules
3. **Configuration**: New options are optional and disabled by default
4. **Environment Variables**: New environment variables for feature control

### Recommended Migration Steps

1. **Update Dependencies**:
   ```bash
   cpanm --installdeps .
   ```

2. **Enable New Features Gradually**:
   ```perl
   # Start with basic new features
   Sentry::SDK->init({
       # Existing configuration
       dsn => $ENV{SENTRY_DSN},
       
       # New features (optional)
       capture_failed_requests => 1,
       max_attachment_size => 10 * 1024 * 1024,  # 10MB
   });
   ```

3. **Monitor Performance**: Watch for any performance impact
4. **Enable Advanced Features**: Gradually enable profiling, cron monitoring

## Dependencies and Requirements

### New CPAN Dependencies
- **Time::HiRes**: High-resolution timing (likely already available)
- **File::Temp**: Temporary file handling for attachments
- **MIME::Types**: Content type detection for attachments
- **Compress::Zlib**: Optional compression for large payloads

### System Requirements
- **Perl Version**: 5.20+ (maintain current requirement)
- **Memory**: Additional 2-5MB for profiling features
- **Disk Space**: Optional offline storage (configurable)

### Optional Dependencies
- **Devel::NYTProf**: Enhanced profiling support
- **JSON::XS**: Faster JSON processing for large payloads

## Risk Assessment and Mitigation

### High-Risk Items

1. **Profiling Implementation**
   - **Risk**: Performance overhead, memory usage
   - **Mitigation**: Sampling, configurable overhead limits, opt-in only

2. **Backward Compatibility**
   - **Risk**: Breaking existing installations
   - **Mitigation**: Comprehensive testing, feature flags, gradual rollout

3. **Memory Usage**
   - **Risk**: Increased memory consumption
   - **Mitigation**: Configurable limits, efficient data structures

### Medium-Risk Items

1. **Network Dependencies**
   - **Risk**: New API endpoints, rate limiting
   - **Mitigation**: Graceful degradation, fallback mechanisms

2. **File System Access**
   - **Risk**: Attachment and offline storage permissions
   - **Mitigation**: Proper error handling, configurable paths

### Low-Risk Items

1. **Configuration Changes**
   - **Risk**: Complex configuration
   - **Mitigation**: Sensible defaults, clear documentation

## Success Metrics

### Feature Adoption
- **Cron Monitoring**: 25% of users enabling check-ins
- **User Feedback**: 15% of users implementing feedback collection
- **Attachments**: 10% of users adding attachments to events

### Performance Metrics
- **Overhead**: <5% performance impact with all features enabled
- **Memory Usage**: <10MB additional memory consumption
- **Startup Time**: <100ms additional initialization time

### Quality Metrics
- **Bug Reports**: <5 critical bugs per quarter after release
- **Test Coverage**: >90% for all new code
- **Documentation**: 100% API documentation coverage

## Timeline and Milestones

### Quarter 1 (Weeks 1-4)
- **Week 1-2**: Core infrastructure improvements
- **Week 3-4**: Cron monitoring implementation
- **Milestone**: Basic cron check-ins working

### Quarter 2 (Weeks 5-8)
- **Week 5-6**: User feedback support
- **Week 7-8**: Attachment implementation
- **Milestone**: User feedback and attachments in beta

### Quarter 3 (Weeks 9-12)
- **Week 9-10**: HTTP client enhancements
- **Week 11-12**: Structured logging support
- **Milestone**: Logging API implemented and tested

### Quarter 4 (Weeks 13-16)
- **Week 13-14**: Profiling support
- **Week 15-16**: Advanced features (offline, feature flags)
- **Milestone**: Production-ready release

## Documentation Plan

### User Documentation
- **README Updates**: Feature overview and quick start
- **POD Documentation**: Complete API reference
- **Migration Guide**: Upgrade instructions and examples
- **Best Practices**: Usage recommendations and patterns

### Developer Documentation
- **Architecture Guide**: Internal design and patterns
- **Contributing Guide**: Development setup and guidelines
- **Testing Guide**: Running and writing tests
- **Release Process**: Version management and deployment

## Release Strategy

### Beta Releases
- **1.4.0-beta1**: Core infrastructure and cron monitoring
- **1.4.0-beta2**: User feedback and attachments  
- **1.4.0-beta3**: HTTP enhancements and structured logging
- **1.4.0-beta4**: Profiling support

### Stable Release
- **1.4.0**: Full feature release with comprehensive documentation
- **1.4.x**: Bug fixes and minor enhancements
- **1.5.0**: Advanced features and performance optimizations

## Conclusion

This modernization plan will bring the Perl Sentry SDK up to par with other language SDKs while maintaining the simplicity and reliability that Perl developers expect. The phased approach ensures that each feature is properly implemented and tested before moving to the next phase.

The plan prioritizes the most requested features (cron monitoring, user feedback, structured logging) while building a solid foundation for future enhancements. **Special emphasis has been placed on distributed tracing capabilities** to enable seamless integration between frontend JavaScript applications and Perl backend services.

### Key Frontend-Backend Integration Features:

- **Complete Distributed Tracing**: Traces initiated in frontend JavaScript applications can be seamlessly continued in Perl backend services
- **Automatic Header Propagation**: `sentry-trace` and `baggage` headers are automatically handled for HTTP requests
- **Framework Integration**: Built-in support for Mojolicious and CGI::Application to extract trace context from incoming requests
- **Cross-Service Observability**: Full trace visibility across microservices, external APIs, and frontend applications
- **Dynamic Sampling Context**: Baggage header support enables advanced sampling strategies across service boundaries

All changes are designed to be backward compatible and opt-in, ensuring that existing users can upgrade safely.

Success of this plan will be measured by adoption rates, performance metrics, and community feedback. Regular check-ins and milestone reviews will ensure the project stays on track and delivers value to the Perl community.
