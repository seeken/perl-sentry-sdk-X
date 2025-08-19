package Sentry::Logger;
use Mojo::Base -base, -signatures;

use Sentry::Logger::LogRecord;
use Sentry::Logger::Buffer;
use Time::HiRes qw(time);

# Class-level logger instance
our $LOGGER;

has 'buffer' => sub { Sentry::Logger::Buffer->new() };
has 'enabled' => 1;
has 'default_level' => 'info';
has 'context' => sub { {} };

# Get or create singleton logger instance
sub logger {
    return $LOGGER //= __PACKAGE__->new();
}

# Set the global logger instance
sub set_logger ($class, $logger) {
    $LOGGER = $logger;
    return $logger;
}

# Core logging method
sub log ($self, $level, $message, $context = {}) {
    return unless $self->enabled;
    
    my $record = Sentry::Logger::LogRecord->new(
        level => $level,
        message => $message,
        context => { %{$self->context}, %$context },
        timestamp => time(),
    );
    
    $self->buffer->add($record);
    return $record;
}

# Template-based structured logging
sub logf ($self, $level, $template, @args) {
    return unless $self->enabled;
    
    my $context = {};
    
    # If last argument is a hash reference, treat as context
    if (@args && ref($args[-1]) eq 'HASH') {
        $context = pop @args;
    }
    
    my $message = sprintf($template, @args);
    
    return $self->log($level, $message, $context);
}

# Convenience methods for different log levels
sub trace ($self, $message, $context = {}) {
    return $self->log('trace', $message, $context);
}

sub debug ($self, $message, $context = {}) {
    return $self->log('debug', $message, $context);
}

sub info ($self, $message, $context = {}) {
    return $self->log('info', $message, $context);
}

sub warn ($self, $message, $context = {}) {
    return $self->log('warn', $message, $context);
}

sub error ($self, $message, $context = {}) {
    return $self->log('error', $message, $context);
}

sub fatal ($self, $message, $context = {}) {
    return $self->log('fatal', $message, $context);
}

# Template-based convenience methods
sub tracef ($self, $template, @args) {
    return $self->logf('trace', $template, @args);
}

sub debugf ($self, $template, @args) {
    return $self->logf('debug', $template, @args);
}

sub infof ($self, $template, @args) {
    return $self->logf('info', $template, @args);
}

sub warnf ($self, $template, @args) {
    return $self->logf('warn', $template, @args);
}

sub errorf ($self, $template, @args) {
    return $self->logf('error', $template, @args);
}

sub fatalf ($self, $template, @args) {
    return $self->logf('fatal', $template, @args);
}

# Contextual logging - create temporary logger with additional context
sub with_context ($self, $additional_context) {
    return __PACKAGE__->new(
        buffer => $self->buffer,
        enabled => $self->enabled,
        context => { %{$self->context}, %$additional_context },
    );
}

# Set persistent context for this logger instance
sub set_context ($self, $context) {
    $self->context($context);
    return $self;
}

# Add to existing context
sub add_context ($self, $additional_context) {
    my $current = $self->context;
    $self->context({ %$current, %$additional_context });
    return $self;
}

# Clear context
sub clear_context ($self) {
    $self->context({});
    return $self;
}

# Transaction/trace-aware logging
sub with_transaction ($self, $transaction_name, $context = {}) {
    require Sentry::Hub;
    my $hub = Sentry::Hub->get_current_hub();
    
    my $transaction_context = {
        transaction => $transaction_name,
        %$context,
    };
    
    if ($hub) {
        my $scope = $hub->get_scope;
        if ($scope && $scope->can('get_transaction')) {
            my $transaction = $scope->get_transaction();
            if ($transaction) {
                $transaction_context->{trace_id} = $transaction->trace_id;
                $transaction_context->{span_id} = $transaction->span_id;
            }
        }
    }
    
    return $self->with_context($transaction_context);
}

# Exception logging with automatic stacktrace
sub log_exception ($self, $exception, $level = 'error', $context = {}) {
    my $message = ref($exception) ? "$exception" : $exception;
    
    my $exception_context = {
        exception => $message,
        %$context,
    };
    
    # Try to get stacktrace if possible
    if (ref($exception) && $exception->can('trace')) {
        my $trace = $exception->trace;
        if ($trace && $trace->can('as_string')) {
            $exception_context->{stacktrace} = $trace->as_string;
        } elsif ($trace) {
            $exception_context->{stacktrace} = "$trace";
        }
    }
    
    return $self->log($level, "Exception: $message", $exception_context);
}

# Performance timing
sub time_block ($self, $name, $code, $context = {}) {
    my $start_time = time();
    
    $self->debug("Starting: $name", { operation => $name, %$context });
    
    my @result;
    my $exception;
    
    eval {
        if (wantarray) {
            @result = $code->();
        } elsif (!wantarray) {
            $result[0] = $code->();
        } else {
            $code->();
        }
    };
    
    if ($@) {
        $exception = $@;
    }
    
    my $duration = time() - $start_time;
    my $timing_context = {
        operation => $name,
        duration_ms => int($duration * 1000),
        %$context,
    };
    
    if ($exception) {
        $self->error("Failed: $name", $timing_context);
        die $exception;
    } else {
        $self->info("Completed: $name", $timing_context);
    }
    
    return wantarray ? @result : $result[0];
}

# Configure logger settings
sub configure ($self, $options = {}) {
    $self->enabled($options->{enabled}) if defined $options->{enabled};
    $self->default_level($options->{default_level}) if defined $options->{default_level};
    
    # Configure buffer if options provided
    if ($options->{buffer}) {
        $self->buffer->configure($options->{buffer});
    }
    
    return $self;
}

# Get logger statistics
sub stats ($self) {
    return {
        enabled => $self->enabled,
        default_level => $self->default_level,
        context_keys => [keys %{$self->context}],
        buffer => $self->buffer->stats(),
    };
}

# Manual buffer control
sub flush ($self) {
    require Sentry::Hub;
    my $hub = Sentry::Hub->get_current_hub();
    return $self->buffer->flush($hub);
}

sub clear_buffer ($self) {
    return $self->buffer->clear();
}

# Graceful shutdown
sub shutdown ($self) {
    $self->buffer->shutdown();
    return $self;
}

# Enable/disable logging
sub enable ($self) {
    $self->enabled(1);
    return $self;
}

sub disable ($self) {
    $self->enabled(0);
    return $self;
}

# Class method shortcuts using singleton
sub class_log ($class, $level, $message, $context = {}) {
    return $class->logger->log($level, $message, $context);
}

sub class_trace ($class, $message, $context = {}) {
    return $class->logger->trace($message, $context);
}

sub class_debug ($class, $message, $context = {}) {
    return $class->logger->debug($message, $context);
}

sub class_info ($class, $message, $context = {}) {
    return $class->logger->info($message, $context);
}

sub class_warn ($class, $message, $context = {}) {
    return $class->logger->warn($message, $context);
}

sub class_error ($class, $message, $context = {}) {
    return $class->logger->error($message, $context);
}

sub class_fatal ($class, $message, $context = {}) {
    return $class->logger->fatal($message, $context);
}

1;

__END__

=encoding utf-8

=head1 NAME

Sentry::Logger - Structured logging with Sentry integration

=head1 SYNOPSIS

  use Sentry::Logger;

  # Get singleton logger
  my $logger = Sentry::Logger->logger;

  # Basic logging
  $logger->info("User logged in", { user_id => 123 });
  $logger->error("Database connection failed", { host => 'db.example.com' });

  # Template-based logging
  $logger->infof("Processing %d items", $count, { batch_id => $batch });

  # Contextual logging
  my $request_logger = $logger->with_context({ request_id => $request_id });
  $request_logger->debug("Processing request");

  # Transaction-aware logging
  my $tx_logger = $logger->with_transaction("payment_process");
  $tx_logger->info("Payment initiated");

  # Exception logging
  $logger->log_exception($@, 'error', { operation => 'save_user' });

  # Performance timing
  my $result = $logger->time_block("database_query", sub {
      return $db->query("SELECT * FROM users");
  });

  # Class method shortcuts
  Sentry::Logger->info("Application started");

=head1 DESCRIPTION

This module provides structured logging with automatic Sentry integration.
Log records are buffered and sent to Sentry with rich context information,
trace correlation, and OpenTelemetry compliance.

=head1 CLASS METHODS

=head2 logger

  my $logger = Sentry::Logger->logger;

Returns the singleton logger instance.

=head2 set_logger

  Sentry::Logger->set_logger($custom_logger);

Sets a custom logger instance as the singleton.

=head1 INSTANCE METHODS

=head2 Basic Logging

=head3 log

  $logger->log($level, $message, $context);

Core logging method. Level should be 'trace', 'debug', 'info', 'warn', 'error', or 'fatal'.

=head3 trace, debug, info, warn, error, fatal

  $logger->info("Message", { key => "value" });

Convenience methods for different log levels.

=head2 Template Logging

=head3 logf

  $logger->logf($level, $template, @args);

Template-based logging with sprintf formatting.

=head3 tracef, debugf, infof, warnf, errorf, fatalf

  $logger->infof("User %s logged in", $username, { session_id => $sid });

Template-based convenience methods.

=head2 Contextual Logging

=head3 with_context

  my $contextual_logger = $logger->with_context({ request_id => $id });

Creates a new logger instance with additional context.

=head3 set_context

  $logger->set_context({ service => "web" });

Sets persistent context for this logger instance.

=head3 add_context

  $logger->add_context({ user_id => 123 });

Adds to existing context.

=head3 clear_context

Clears all context from this logger instance.

=head2 Transaction Integration

=head3 with_transaction

  my $tx_logger = $logger->with_transaction("payment_flow");

Creates logger with transaction context and trace correlation.

=head2 Exception Handling

=head3 log_exception

  $logger->log_exception($exception, 'error', { operation => 'save' });

Logs exceptions with automatic stacktrace extraction.

=head2 Performance Monitoring

=head3 time_block

  my $result = $logger->time_block("operation", sub { ... }, $context);

Times code execution and logs duration automatically.

=head2 Buffer Management

=head3 flush

  my $count = $logger->flush();

Manually flushes buffered log records to Sentry.

=head3 clear_buffer

Clears buffer without sending (useful for testing).

=head2 Configuration

=head3 configure

  $logger->configure({
      enabled => 1,
      buffer => { max_size => 50, min_level => 'warn' }
  });

Updates logger configuration.

=head3 enable, disable

Enables or disables logging.

=head2 Utilities

=head3 stats

Returns statistics about logger state and buffer.

=head3 shutdown

Performs graceful shutdown by flushing remaining records.

=head1 CLASS METHOD SHORTCUTS

All logging methods are available as class methods using the singleton:

  Sentry::Logger->info("Message");
  Sentry::Logger->errorf("Error: %s", $error);

=head1 THREAD SAFETY

This logger is designed to be thread-safe when using the singleton pattern.
Each thread should use Sentry::Logger->logger to get the shared instance.

=head1 INTEGRATION

The logger automatically integrates with:

=over 4

=item * Sentry Hub for trace correlation

=item * Sentry Transport for delivery

=item * Sentry Scope for context enrichment

=item * OpenTelemetry severity levels

=back

=head1 AUTHOR

Philipp Busse E<lt>pmb@heise.deE<gt>

=head1 COPYRIGHT

Copyright 2021- Philipp Busse

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
