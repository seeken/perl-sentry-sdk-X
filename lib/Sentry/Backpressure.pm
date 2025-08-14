package Sentry::Backpressure;
use Mojo::Base -base, -signatures;

use Time::HiRes qw(time);

has max_queue_size => 100;
has queue_size => 0;
has dropped_events => 0;
has pressure_level => 0;  # 0 = none, 1 = low, 2 = medium, 3 = high
has sample_rates => sub { {} };  # dynamic sample rates by event type
has last_pressure_check => sub { time() };

# Pressure thresholds
use constant {
    LOW_PRESSURE_THRESHOLD => 0.5,     # 50% of max queue
    MEDIUM_PRESSURE_THRESHOLD => 0.75, # 75% of max queue  
    HIGH_PRESSURE_THRESHOLD => 0.9,    # 90% of max queue
};

sub should_drop_event ($self, $event_type = 'error') {
    $self->_update_pressure_level();
    
    # Always drop if at maximum capacity
    return 1 if $self->queue_size >= $self->max_queue_size;
    
    # Apply dynamic sampling based on pressure level
    my $sample_rate = $self->_get_dynamic_sample_rate($event_type);
    return rand() > $sample_rate;
}

sub increment_queue ($self) {
    $self->queue_size($self->queue_size + 1);
    $self->_update_pressure_level();
}

sub decrement_queue ($self) {
    my $new_size = $self->queue_size - 1;
    $self->queue_size($new_size < 0 ? 0 : $new_size);
    $self->_update_pressure_level();
}

sub record_dropped_event ($self) {
    $self->dropped_events($self->dropped_events + 1);
}

sub _update_pressure_level ($self) {
    my $ratio = $self->queue_size / $self->max_queue_size;
    my $old_level = $self->pressure_level;
    
    if ($ratio >= HIGH_PRESSURE_THRESHOLD) {
        $self->pressure_level(3);
    } elsif ($ratio >= MEDIUM_PRESSURE_THRESHOLD) {
        $self->pressure_level(2);
    } elsif ($ratio >= LOW_PRESSURE_THRESHOLD) {
        $self->pressure_level(1);
    } else {
        $self->pressure_level(0);
    }
    
    # Update dynamic sample rates when pressure changes
    if ($self->pressure_level != $old_level) {
        $self->_update_dynamic_sample_rates();
    }
    
    $self->last_pressure_check(time());
}

sub _update_dynamic_sample_rates ($self) {
    my $level = $self->pressure_level;
    my $rates = $self->sample_rates;
    
    # Adjust sample rates based on pressure level
    if ($level == 0) {
        # No pressure - normal rates
        $rates->{error} = 1.0;
        $rates->{transaction} = 1.0;
        $rates->{session} = 1.0;
    } elsif ($level == 1) {
        # Low pressure - slight reduction
        $rates->{error} = 0.9;
        $rates->{transaction} = 0.8;
        $rates->{session} = 0.7;
    } elsif ($level == 2) {
        # Medium pressure - significant reduction
        $rates->{error} = 0.7;
        $rates->{transaction} = 0.5;
        $rates->{session} = 0.3;
    } else {
        # High pressure - aggressive reduction
        $rates->{error} = 0.3;
        $rates->{transaction} = 0.1;
        $rates->{session} = 0.05;
    }
}

sub _get_dynamic_sample_rate ($self, $event_type) {
    return $self->sample_rates->{$event_type} // 1.0;
}

sub get_pressure_stats ($self) {
    return {
        queue_size => $self->queue_size,
        max_queue_size => $self->max_queue_size,
        pressure_level => $self->pressure_level,
        pressure_ratio => $self->queue_size / $self->max_queue_size,
        dropped_events => $self->dropped_events,
        sample_rates => { %{$self->sample_rates} },
    };
}

sub adjust_max_queue_size ($self, $new_size) {
    $self->max_queue_size($new_size > 0 ? $new_size : 1);
    $self->_update_pressure_level();
}

sub reset_stats ($self) {
    $self->dropped_events(0);
    $self->queue_size(0);
    $self->pressure_level(0);
    $self->sample_rates({});
}

1;

__END__

=encoding utf-8

=head1 NAME

Sentry::Backpressure - Backpressure management for Sentry SDK

=head1 SYNOPSIS

  use Sentry::Backpressure;
  
  my $backpressure = Sentry::Backpressure->new(max_queue_size => 50);
  
  # Check if we should drop an event
  if ($backpressure->should_drop_event('error')) {
      $backpressure->record_dropped_event();
      return;
  }
  
  # Track queue operations
  $backpressure->increment_queue();
  # ... process event ...
  $backpressure->decrement_queue();
  
  # Get current stats
  my $stats = $backpressure->get_pressure_stats();

=head1 DESCRIPTION

This module manages backpressure for the Sentry SDK by dynamically adjusting
sample rates based on queue pressure. It helps prevent memory issues and
maintains performance under high load.

=head1 METHODS

=head2 should_drop_event

  my $should_drop = $backpressure->should_drop_event($event_type);

Returns true if the event should be dropped based on current pressure levels.

=head2 increment_queue / decrement_queue

Track queue size changes for pressure calculation.

=head2 get_pressure_stats

Returns a hashref with current pressure statistics.

=cut
