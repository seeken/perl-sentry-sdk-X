package Sentry::Logger::Buffer;
use Mojo::Base -base, -signatures;

use Time::HiRes;

has 'records' => sub { [] };
has 'max_size' => 100;                    # Maximum records before auto-flush
has 'flush_interval' => 30;               # Seconds between auto-flushes
has 'min_level' => 'info';                # Minimum level to buffer
has 'last_flush' => sub { time() };
has 'auto_flush' => 1;                    # Enable automatic flushing

# Add a log record to the buffer
sub add ($self, $record) {
    return unless $record;
    return unless $record->should_send($self->min_level);
    
    # Add scope context to the record
    $record->add_scope_context();
    
    push @{$self->records}, $record;
    
    # Check if we need to flush
    if ($self->auto_flush) {
        if ($self->should_flush()) {
            $self->flush();
        }
    }
    
    return $self;
}

# Check if buffer should be flushed
sub should_flush ($self) {
    my $record_count = scalar @{$self->records};
    my $time_since_flush = time() - $self->last_flush;
    
    return $record_count >= $self->max_size || 
           $time_since_flush >= $self->flush_interval ||
           $record_count > 0 && $self->has_high_severity_logs();
}

# Check if buffer has error/fatal logs (flush immediately)
sub has_high_severity_logs ($self) {
    for my $record (@{$self->records}) {
        return 1 if $record->level eq 'error' || $record->level eq 'fatal';
    }
    return 0;
}

# Flush all buffered records to Sentry
sub flush ($self, $hub = undef) {
    my $records = $self->records;
    return 0 unless @$records;
    
    # Reset buffer first to avoid losing logs if sending fails
    $self->records([]);
    $self->last_flush(time());
    
    # Use provided hub or try to get hub from current context
    unless ($hub) {
        require Sentry::Hub;
        $hub = Sentry::Hub->get_current_hub();
    }
    return 0 unless $hub;
    
    my $client = $hub->client;
    return 0 unless $client;
    
    # Create envelope for log records
    my $envelope = $client->_prepare_envelope();
    
    # Add each log record as a structured log item
    for my $record (@$records) {
        $envelope->add_item('log', $record->to_envelope_item());
    }
    
    # Send the envelope
    $client->_send_envelope($envelope);
    
    require Sentry::Logger;
    Sentry::Logger->logger->debug("Flushed " . scalar(@$records) . " log records to Sentry", {
        component => 'Logger::Buffer',
        record_count => scalar(@$records),
    });
    
    return scalar(@$records);
}

# Manually flush buffer (useful for shutdown)
sub force_flush ($self) {
    return $self->flush();
}

# Get buffer statistics
sub stats ($self) {
    return {
        record_count => scalar @{$self->records},
        last_flush => $self->last_flush,
        time_since_flush => time() - $self->last_flush,
        buffer_size => $self->max_size,
        min_level => $self->min_level,
    };
}

# Clear buffer without sending (useful for testing)
sub clear ($self) {
    $self->records([]);
    $self->last_flush(time());
    return $self;
}

# Filter records by level
sub filter_by_level ($self, $level) {
    my %level_priorities = (
        trace => 1, debug => 2, info => 3,
        warn => 4, error => 5, fatal => 6,
    );
    
    my $min_priority = $level_priorities{$level} // 3;
    
    my @filtered = grep {
        my $record_priority = $level_priorities{$_->level} // 0;
        $record_priority >= $min_priority;
    } @{$self->records};
    
    return \@filtered;
}

# Get records within time range
sub filter_by_time ($self, $start_time, $end_time = undef) {
    $end_time //= time();
    
    my @filtered = grep {
        $_->timestamp >= $start_time && $_->timestamp <= $end_time;
    } @{$self->records};
    
    return \@filtered;
}

# Enable/disable auto-flushing
sub set_auto_flush ($self, $enabled) {
    $self->auto_flush($enabled);
    return $self;
}

# Update buffer configuration
sub configure ($self, $options = {}) {
    $self->max_size($options->{max_size}) if defined $options->{max_size};
    $self->flush_interval($options->{flush_interval}) if defined $options->{flush_interval};
    $self->min_level($options->{min_level}) if defined $options->{min_level};
    $self->auto_flush($options->{auto_flush}) if defined $options->{auto_flush};
    
    return $self;
}

# Cleanup method for graceful shutdown
sub shutdown ($self) {
    # Force flush any remaining records
    if (@{$self->records}) {
        $self->force_flush();
    }
    
    $self->clear();
    return $self;
}

1;

__END__

=encoding utf-8

=head1 NAME

Sentry::Logger::Buffer - Buffer for collecting and batching log records

=head1 SYNOPSIS

  use Sentry::Logger::Buffer;

  my $buffer = Sentry::Logger::Buffer->new(
      max_size => 50,
      flush_interval => 30,
      min_level => 'warn',
  );

  # Add log records
  $buffer->add($log_record);

  # Manual flush
  my $sent_count = $buffer->flush();

  # Get buffer statistics
  my $stats = $buffer->stats();

=head1 DESCRIPTION

This class buffers log records and automatically flushes them to Sentry based
on configurable criteria (buffer size, time interval, or log severity).

=head1 ATTRIBUTES

=head2 max_size

Maximum number of records to buffer before auto-flushing. Default: 100.

=head2 flush_interval

Number of seconds between automatic flushes. Default: 30.

=head2 min_level

Minimum log level to buffer ('trace', 'debug', 'info', 'warn', 'error', 'fatal').
Default: 'info'.

=head2 auto_flush

Whether to automatically flush based on size/time criteria. Default: 1 (enabled).

=head1 METHODS

=head2 add

  $buffer->add($log_record);

Adds a log record to the buffer. May trigger automatic flush.

=head2 flush

  my $count = $buffer->flush();

Flushes all buffered records to Sentry and returns the number sent.

=head2 should_flush

Returns true if the buffer should be flushed based on current criteria.

=head2 force_flush

Manually flushes the buffer regardless of auto-flush settings.

=head2 stats

Returns a hash reference with buffer statistics.

=head2 clear

Clears the buffer without sending records (useful for testing).

=head2 configure

  $buffer->configure({
      max_size => 200,
      min_level => 'error',
  });

Updates buffer configuration.

=head2 shutdown

Performs graceful shutdown by flushing any remaining records.

=head1 FILTERING METHODS

=head2 filter_by_level

  my $records = $buffer->filter_by_level('error');

Returns records at or above the specified level.

=head2 filter_by_time

  my $records = $buffer->filter_by_time($start_time, $end_time);

Returns records within the specified time range.

=head1 AUTHOR

Philipp Busse E<lt>pmb@heise.deE<gt>

=head1 COPYRIGHT

Copyright 2021- Philipp Busse

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
