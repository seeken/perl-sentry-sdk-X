package Sentry::Logger::LogRecord;
use Mojo::Base -base, -signatures;

use Time::HiRes;
use POSIX qw(strftime);

has 'timestamp' => sub { Time::HiRes::time() };
has 'level' => undef;           # trace, debug, info, warn, error, fatal
has 'severity_number' => undef; # 1, 5, 9, 13, 17, 21
has 'message' => undef;         # The actual log message
has 'body' => undef;            # Alternative name for message (OpenTelemetry)
has 'context' => sub { {} };    # Additional context (non-OpenTelemetry convenience)
has 'trace_id' => undef;        # Current trace ID if available
has 'span_id' => undef;         # Current span ID if available
has 'attributes' => sub { {} };  # Additional structured data
has 'resource' => sub { {} };    # Resource attributes

# OpenTelemetry severity levels
use constant {
    SEVERITY_TRACE => 1,
    SEVERITY_DEBUG => 5,
    SEVERITY_INFO => 9,
    SEVERITY_WARN => 13,
    SEVERITY_ERROR => 17,
    SEVERITY_FATAL => 21,
};

# Override new to call BUILD
sub new ($class, @args) {
    my $self = $class->SUPER::new(@args);
    $self->BUILD(\@args) if $self->can('BUILD');
    return $self;
}

# Ensure consistency between message/body and set severity_number
sub BUILD ($self, $args) {
    # Synchronize message and body
    if (defined $self->message && !defined $self->body) {
        $self->body($self->message);
    } elsif (defined $self->body && !defined $self->message) {
        $self->message($self->body);
    }
    
    # Set severity_number based on level
    if (defined $self->level && !defined $self->severity_number) {
        my %severity_map = (
            trace => SEVERITY_TRACE,
            debug => SEVERITY_DEBUG,
            info  => SEVERITY_INFO,
            warn  => SEVERITY_WARN,
            error => SEVERITY_ERROR,
            fatal => SEVERITY_FATAL,
        );
        $self->severity_number($severity_map{$self->level} // SEVERITY_INFO);
    }
    
    # Merge context into attributes for convenience
    if ($self->context && %{$self->context}) {
        my $attrs = $self->attributes;
        $self->attributes({ %$attrs, %{$self->context} });
    }
}

sub to_hash ($self) {
    my $hash = {
        timestamp => $self->timestamp,
        level => $self->level,
        severity_number => $self->severity_number,
        body => $self->body,
        attributes => $self->attributes,
        resource => $self->resource,
    };
    
    # Add trace context if available
    $hash->{trace_id} = $self->trace_id if defined $self->trace_id;
    $hash->{span_id} = $self->span_id if defined $self->span_id;
    
    return $hash;
}

sub to_envelope_item ($self) {
    # Create a proper structured log item following OpenTelemetry format
    my $item = {
        # OpenTelemetry log format fields
        severity_text => $self->level,                    # trace, debug, info, warn, error, fatal
        severity_number => $self->severity_number,        # 1, 5, 9, 13, 17, 21
        body => $self->message // $self->body,            # The log message
        attributes => $self->attributes // {},            # Additional structured data
        time_unix_nano => int($self->timestamp * 1_000_000_000),  # Nanoseconds since epoch
        
        # Additional Sentry-specific fields
        logger => 'perl-sentry-structured-logging',
        platform => 'perl',
    };
    
    # Add trace context if available
    if (defined $self->trace_id) {
        $item->{trace_id} = $self->trace_id;
        $item->{span_id} = $self->span_id if defined $self->span_id;
    }
    
    return $item;
}

# Check if this record should be sent based on level filtering
sub should_send ($self, $min_level = 'info') {
    my %level_priorities = (
        trace => 1,
        debug => 2,
        info => 3,
        warn => 4,
        error => 5,
        fatal => 6,
    );
    
    my $current_priority = $level_priorities{$self->level} // 0;
    my $min_priority = $level_priorities{$min_level} // 3;
    
    return $current_priority >= $min_priority;
}

# Add current scope context from Sentry Hub
sub add_scope_context ($self) {
    eval {
        require Sentry::Hub;
        my $hub = Sentry::Hub->get_current_hub();
        return unless $hub;
        
        # Try both scope and get_scope methods (different Hub implementations)
        my $scope = $hub->can('scope') ? $hub->scope : $hub->can('get_scope') ? $hub->get_scope : undef;
        return unless $scope;
        
        # Add user context safely
        if ($scope->can('user') && (my $user = $scope->user)) {
            $self->attributes->{'user.id'} = $user->{id} if $user->{id};
            $self->attributes->{'user.email'} = $user->{email} if $user->{email};
            $self->attributes->{'user.username'} = $user->{username} if $user->{username};
        }
        
        # Add tags safely
        if ($scope->can('tags') && (my $tags = $scope->tags)) {
            for my $key (keys %$tags) {
                $self->attributes->{"tag.$key"} = $tags->{$key};
            }
        }
        
        # Add extra context safely
        if ($scope->can('extra') && (my $extra = $scope->extra)) {
            for my $key (keys %$extra) {
                $self->attributes->{"extra.$key"} = $extra->{$key};
            }
        }
        
        # Add trace context if available
        if ($scope->can('span') && (my $span = $scope->span)) {
            $self->trace_id($span->trace_id) if $span->can('trace_id');
            $self->span_id($span->span_id) if $span->can('span_id');
            
            $self->attributes->{'sentry.trace.parent_span_id'} = $span->span_id if $span->can('span_id');
        }
        
        # Try to get transaction context as well
        if ($scope->can('get_transaction') && (my $transaction = $scope->get_transaction)) {
            $self->trace_id($transaction->trace_id) if $transaction->can('trace_id');
            $self->attributes->{'sentry.transaction'} = $transaction->name if $transaction->can('name');
        }
    };
    
    # Ignore errors - scope context is optional
    return $self;
}

1;

__END__

=encoding utf-8

=head1 NAME

Sentry::Logger::LogRecord - Structured log record for Sentry

=head1 SYNOPSIS

  use Sentry::Logger::LogRecord;

  my $record = Sentry::Logger::LogRecord->new(
      level => 'info',
      message => 'User logged in',
      context => { user_id => 123, action => 'login' },
  );

  # Add current scope context
  $record->add_scope_context();

  # Convert to envelope format
  my $envelope_item = $record->to_envelope_item();

=head1 DESCRIPTION

This class represents a structured log record that integrates with Sentry's
envelope system. It supports OpenTelemetry severity levels and automatic
context enrichment from Sentry scopes.

=head1 ATTRIBUTES

=head2 timestamp

Unix timestamp with microsecond precision. Defaults to current time.

=head2 level

Log level string: 'trace', 'debug', 'info', 'warn', 'error', 'fatal'.

=head2 severity_number

OpenTelemetry severity number (1, 5, 9, 13, 17, 21). Auto-set from level.

=head2 message

The log message text.

=head2 body

Alternative name for message (OpenTelemetry compatibility).

=head2 context

Additional context data (convenience). Merged into attributes during construction.

=head2 trace_id

Current trace ID if available.

=head2 span_id

Current span ID if available.

=head2 attributes

Structured attributes following OpenTelemetry format.

=head2 resource

Resource attributes.

=head1 METHODS

=head2 new

  my $record = Sentry::Logger::LogRecord->new(%args);

Creates a new log record. Automatically calls BUILD to set up defaults.

=head2 to_hash

  my $hash = $record->to_hash();

Converts the record to a hash representation.

=head2 to_envelope_item

  my $item = $record->to_envelope_item();

Converts the record to Sentry envelope item format.

=head2 should_send

  if ($record->should_send('warn')) { ... }

Checks if this record should be sent based on minimum level filtering.

=head2 add_scope_context

  $record->add_scope_context();

Adds context from the current Sentry scope (user, tags, extra, traces).

=head1 CONSTANTS

=over 4

=item SEVERITY_TRACE = 1

=item SEVERITY_DEBUG = 5

=item SEVERITY_INFO = 9

=item SEVERITY_WARN = 13

=item SEVERITY_ERROR = 17

=item SEVERITY_FATAL = 21

=back

=head1 AUTHOR

Philipp Busse E<lt>pmb@heise.deE<gt>

=head1 COPYRIGHT

Copyright 2021- Philipp Busse

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
