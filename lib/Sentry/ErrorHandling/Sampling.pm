package Sentry::ErrorHandling::Sampling;
use Mojo::Base -base, -signatures;

use Time::HiRes qw(time);
use List::Util qw(min max);

=head1 NAME

Sentry::ErrorHandling::Sampling - Intelligent error sampling and rate limiting

=head1 DESCRIPTION

Provides smart sampling strategies to prevent error spam while ensuring
critical errors are always captured. Includes rate-based sampling,
priority-based sampling, and custom sampling rules.

=cut

# Sampling strategies
has strategies => sub { [
  'rate_based',
  'priority_based', 
  'error_type_based',
  'frequency_based',
  'custom_rules_based'
] };

# Sampling configuration
has config => sub { {
  # Base sample rate (0.0 to 1.0)
  base_sample_rate => 1.0,
  
  # Maximum errors per minute
  max_errors_per_minute => 100,
  
  # Critical error sample rate (always higher)
  critical_sample_rate => 1.0,
  
  # Error type specific rates
  error_type_rates => {
    'DBI::Exception' => 0.8,
    'Mojo::Exception' => 0.6,
    'die' => 0.4,
    'warn' => 0.1,
  },
  
  # Priority levels
  priority_rates => {
    'critical' => 1.0,
    'high' => 0.8,
    'medium' => 0.5,
    'low' => 0.2,
  },
  
  # Burst protection
  burst_protection => {
    enabled => 1,
    window_size => 60,      # seconds
    burst_threshold => 10,  # errors in window
    burst_sample_rate => 0.1,  # reduced rate during burst
  },
  
  # Adaptive sampling
  adaptive_sampling => {
    enabled => 1,
    target_rate => 50,      # target errors per minute
    adjustment_factor => 0.1, # how much to adjust
    min_sample_rate => 0.01,
    max_sample_rate => 1.0,
  },
} };

# Sampling state tracking
has _error_counters => sub { {} };
has _burst_windows => sub { {} };
has _adaptive_state => sub { { 
  current_rate => 1.0,
  last_adjustment => time(),
} };

# Custom sampling rules
has custom_rules => sub { [] };

=head2 should_sample($exception, $event_data, $options)

Determine if an error should be sampled based on multiple strategies.

Returns a hash with sampling decision and metadata.

=cut

sub should_sample ($self, $exception, $event_data, $options = {}) {
  my $now = time();
  my $result = {
    should_sample => 1,
    sample_rate => 1.0,
    reason => 'default',
    metadata => {},
  };
  
  # Strategy 1: Check burst protection first
  if ($self->config->{burst_protection}{enabled}) {
    my $burst_result = $self->_check_burst_protection($exception, $event_data, $now);
    if (!$burst_result->{should_sample}) {
      return $burst_result;
    }
    $result->{metadata}{burst_protected} = $burst_result->{metadata};
  }
  
  # Strategy 2: Priority-based sampling
  if (my $priority_result = $self->_sample_by_priority($exception, $event_data, $options)) {
    $result = { %$result, %$priority_result };
    if ($result->{sample_rate} >= 1.0) {
      return $result;  # High priority, always sample
    }
  }
  
  # Strategy 3: Error type-based sampling
  if (my $type_result = $self->_sample_by_error_type($exception, $event_data)) {
    $result->{sample_rate} = min($result->{sample_rate}, $type_result->{sample_rate});
    $result->{reason} = $type_result->{reason} if $type_result->{sample_rate} < $result->{sample_rate};
  }
  
  # Strategy 4: Frequency-based sampling
  if (my $freq_result = $self->_sample_by_frequency($exception, $event_data, $now)) {
    $result->{sample_rate} = min($result->{sample_rate}, $freq_result->{sample_rate});
    $result->{reason} = $freq_result->{reason} if $freq_result->{sample_rate} < $result->{sample_rate};
  }
  
  # Strategy 5: Adaptive sampling
  if ($self->config->{adaptive_sampling}{enabled}) {
    my $adaptive_rate = $self->_get_adaptive_sample_rate($now);
    $result->{sample_rate} = min($result->{sample_rate}, $adaptive_rate);
    $result->{metadata}{adaptive_rate} = $adaptive_rate;
  }
  
  # Strategy 6: Custom rules
  for my $rule (@{$self->custom_rules}) {
    if (my $custom_result = $rule->($exception, $event_data, $options, $result)) {
      $result = { %$result, %$custom_result };
    }
  }
  
  # Rate limiting protection
  if (!$self->_check_rate_limit($now)) {
    $result = {
      should_sample => 0,
      sample_rate => 0.0,
      reason => 'rate_limited',
      metadata => { rate_limit_exceeded => 1 },
    };
  }
  
  # Final sampling decision
  $result->{should_sample} = rand() < $result->{sample_rate};
  
  # Update counters
  $self->_update_counters($exception, $event_data, $now, $result);
  
  return $result;
}

=head2 Sampling strategy implementations

=cut

sub _check_burst_protection ($self, $exception, $event_data, $now) {
  my $config = $self->config->{burst_protection};
  return { should_sample => 1 } unless $config->{enabled};
  
  my $error_key = $self->_get_error_key($exception, $event_data);
  my $window_key = "$error_key:burst";
  
  # Initialize or clean up window
  if (!$self->_burst_windows->{$window_key}) {
    $self->_burst_windows->{$window_key} = [];
  }
  
  my $window = $self->_burst_windows->{$window_key};
  
  # Remove old entries
  @$window = grep { $now - $_ < $config->{window_size} } @$window;
  
  # Check if we're in burst mode
  if (@$window >= $config->{burst_threshold}) {
    return {
      should_sample => rand() < $config->{burst_sample_rate},
      sample_rate => $config->{burst_sample_rate},
      reason => 'burst_protection',
      metadata => {
        burst_mode => 1,
        errors_in_window => scalar(@$window),
      },
    };
  }
  
  # Add current error to window
  push @$window, $now;
  
  return {
    should_sample => 1,
    metadata => {
      burst_mode => 0,
      errors_in_window => scalar(@$window),
    },
  };
}

sub _sample_by_priority ($self, $exception, $event_data, $options) {
  my $priority = $self->_determine_error_priority($exception, $event_data, $options);
  my $rates = $self->config->{priority_rates};
  
  if (my $rate = $rates->{$priority}) {
    return {
      sample_rate => $rate,
      reason => "priority_$priority",
      metadata => { error_priority => $priority },
    };
  }
  
  return undef;
}

sub _sample_by_error_type ($self, $exception, $event_data) {
  my $error_type = $self->_get_error_type($exception, $event_data);
  my $rates = $self->config->{error_type_rates};
  
  # Check exact match first
  if (my $rate = $rates->{$error_type}) {
    return {
      sample_rate => $rate,
      reason => "error_type_$error_type",
      metadata => { error_type => $error_type },
    };
  }
  
  # Check pattern matches
  for my $pattern (keys %$rates) {
    if ($error_type =~ /$pattern/) {
      return {
        sample_rate => $rates->{$pattern},
        reason => "error_pattern_$pattern",
        metadata => { error_type => $error_type, matched_pattern => $pattern },
      };
    }
  }
  
  return undef;
}

sub _sample_by_frequency ($self, $exception, $event_data, $now) {
  my $error_key = $self->_get_error_key($exception, $event_data);
  my $counter_key = "$error_key:freq";
  
  # Initialize counter if needed
  if (!$self->_error_counters->{$counter_key}) {
    $self->_error_counters->{$counter_key} = {
      count => 0,
      first_seen => $now,
      last_seen => $now,
      sample_rate => 1.0,
    };
  }
  
  my $counter = $self->_error_counters->{$counter_key};
  $counter->{count}++;
  $counter->{last_seen} = $now;
  
  # Calculate frequency-based sample rate
  my $time_span = $now - $counter->{first_seen};
  my $frequency = 0;
  if ($time_span > 0) {
    $frequency = $counter->{count} / max($time_span / 60, 1); # errors per minute
    
    # Reduce sampling rate for high-frequency errors
    if ($frequency > 60) {
      $counter->{sample_rate} = 0.01;  # 1% for very frequent errors
    } elsif ($frequency > 30) {
      $counter->{sample_rate} = 0.05;  # 5% for frequent errors
    } elsif ($frequency > 10) {
      $counter->{sample_rate} = 0.2;   # 20% for moderately frequent errors
    } else {
      $counter->{sample_rate} = 1.0;   # 100% for infrequent errors
    }
  }
  
  return {
    sample_rate => $counter->{sample_rate},
    reason => 'frequency_based',
    metadata => {
      error_frequency => $frequency // 0,
      error_count => $counter->{count},
      time_span => $time_span,
    },
  };
}

sub _get_adaptive_sample_rate ($self, $now) {
  my $config = $self->config->{adaptive_sampling};
  my $state = $self->_adaptive_state;
  
  # Check if it's time to adjust
  if ($now - $state->{last_adjustment} > 60) {  # Adjust every minute
    my $current_rate = $self->_calculate_current_error_rate($now);
    my $target_rate = $config->{target_rate};
    
    if ($current_rate > $target_rate) {
      # Too many errors, reduce sample rate
      $state->{current_rate} *= (1 - $config->{adjustment_factor});
    } elsif ($current_rate < $target_rate * 0.8) {
      # Too few errors, increase sample rate
      $state->{current_rate} *= (1 + $config->{adjustment_factor});
    }
    
    # Clamp to limits
    $state->{current_rate} = max($config->{min_sample_rate}, 
                                min($config->{max_sample_rate}, 
                                   $state->{current_rate}));
    
    $state->{last_adjustment} = $now;
  }
  
  return $state->{current_rate};
}

sub _check_rate_limit ($self, $now) {
  my $max_per_minute = $self->config->{max_errors_per_minute};
  return 1 unless $max_per_minute;
  
  # Clean up old entries
  $self->_error_counters->{_global_rate} //= [];
  my $global_counter = $self->_error_counters->{_global_rate};
  @$global_counter = grep { $now - $_ < 60 } @$global_counter;
  
  return @$global_counter < $max_per_minute;
}

=head2 Helper methods

=cut

sub _get_error_key ($self, $exception, $event_data) {
  # Create a key to identify similar errors for frequency tracking
  
  my @key_parts;
  
  # Error type
  if (my $type = $self->_get_error_type($exception, $event_data)) {
    push @key_parts, "type:$type";
  }
  
  # Error message (normalized)
  if (my $message = $self->_get_error_message($exception, $event_data)) {
    # Normalize message for grouping
    $message =~ s/\d+/NUM/g;  # Replace numbers
    $message =~ s/0x[0-9a-f]+/ADDR/gi;  # Replace addresses
    $message = substr($message, 0, 100);  # Limit length
    push @key_parts, "msg:$message";
  }
  
  # Location (file:line)
  if (my $location = $self->_get_error_location($exception, $event_data)) {
    push @key_parts, "loc:$location";
  }
  
  return join('|', @key_parts) || 'unknown_error';
}

sub _get_error_type ($self, $exception, $event_data) {
  # From exception object
  if (ref $exception) {
    return ref $exception;
  }
  
  # From event data
  if (my $exc_type = $event_data->{exception}{values}[0]{type}) {
    return $exc_type;
  }
  
  # Default based on how it was captured
  return 'die';
}

sub _get_error_message ($self, $exception, $event_data) {
  # From exception object
  if (ref $exception && $exception->can('message')) {
    return $exception->message;
  }
  
  # From string
  if (!ref $exception) {
    return $exception;
  }
  
  # From event data
  if (my $message = $event_data->{message}) {
    return ref $message eq 'HASH' ? $message->{formatted} : $message;
  }
  
  if (my $exc_value = $event_data->{exception}{values}[0]{value}) {
    return $exc_value;
  }
  
  return undef;
}

sub _get_error_location ($self, $exception, $event_data) {
  # Try to get file and line from stack trace
  my $frames = $self->_get_stack_frames($exception, $event_data);
  return undef unless $frames && @$frames;
  
  # Get the top frame (where error occurred)
  my $frame = $frames->[0];
  
  my ($filename, $lineno);
  if (ref $frame eq 'HASH') {
    $filename = $frame->{filename};
    $lineno = $frame->{lineno};
  } elsif (ref $frame eq 'ARRAY') {
    $filename = $frame->[1];
    $lineno = $frame->[2];
  }
  
  return undef unless $filename;
  
  # Normalize filename
  $filename =~ s{^.*/}{};  # Remove path
  
  return defined $lineno ? "$filename:$lineno" : $filename;
}

sub _get_stack_frames ($self, $exception, $event_data) {
  # From Mojo::Exception
  if (ref $exception eq 'Mojo::Exception' && $exception->can('frames')) {
    return $exception->frames;
  }
  
  # From event data
  if (my $stacktrace = $event_data->{exception}{values}[0]{stacktrace}) {
    return $stacktrace->{frames} if ref $stacktrace eq 'HASH';
    return $stacktrace->frames if ref $stacktrace && $stacktrace->can('frames');
  }
  
  return undef;
}

sub _determine_error_priority ($self, $exception, $event_data, $options) {
  # Explicit priority from options
  return $options->{priority} if $options->{priority};
  
  # Database errors are often critical
  if ($self->_is_database_error($exception, $event_data)) {
    return 'high';
  }
  
  # HTTP 5xx errors are high priority
  if (my $status = $event_data->{contexts}{response}{status_code}) {
    return 'critical' if $status >= 500;
    return 'high' if $status >= 400;
  }
  
  # Security-related errors
  if ($self->_is_security_error($exception, $event_data)) {
    return 'critical';
  }
  
  # Warnings are low priority
  if ($self->_is_warning($exception, $event_data)) {
    return 'low';
  }
  
  # Default priority
  return 'medium';
}

sub _is_database_error ($self, $exception, $event_data) {
  my $error_type = $self->_get_error_type($exception, $event_data);
  return $error_type =~ /DBI|DBD|Database/i;
}

sub _is_security_error ($self, $exception, $event_data) {
  my $message = $self->_get_error_message($exception, $event_data) || '';
  return $message =~ /unauthorized|forbidden|authentication|permission|security/i;
}

sub _is_warning ($self, $exception, $event_data) {
  return $event_data->{level} && $event_data->{level} eq 'warning';
}

sub _calculate_current_error_rate ($self, $now) {
  # Count errors in the last minute across all counters
  my $count = 0;
  
  for my $key (keys %{$self->_error_counters}) {
    next if $key eq '_global_rate';
    
    my $counter = $self->_error_counters->{$key};
    if (ref $counter eq 'HASH' && $counter->{last_seen} && $now - $counter->{last_seen} < 60) {
      $count += $counter->{count};
    }
  }
  
  return $count;
}

sub _update_counters ($self, $exception, $event_data, $now, $result) {
  # Update global rate counter
  $self->_error_counters->{_global_rate} //= [];
  push @{$self->_error_counters->{_global_rate}}, $now;
  
  # Clean up old counters periodically
  if (rand() < 0.01) {  # 1% chance
    $self->_cleanup_old_counters($now);
  }
}

sub _cleanup_old_counters ($self, $now) {
  my $cutoff = $now - 3600;  # Keep data for 1 hour
  
  for my $key (keys %{$self->_error_counters}) {
    my $counter = $self->_error_counters->{$key};
    
    if (ref $counter eq 'HASH' && $counter->{last_seen} && $counter->{last_seen} < $cutoff) {
      delete $self->_error_counters->{$key};
    } elsif (ref $counter eq 'ARRAY') {
      @$counter = grep { $_ > $cutoff } @$counter;
      delete $self->_error_counters->{$key} unless @$counter;
    }
  }
  
  # Clean up burst windows
  for my $key (keys %{$self->_burst_windows}) {
    my $window = $self->_burst_windows->{$key};
    @$window = grep { $_ > $cutoff } @$window;
    delete $self->_burst_windows->{$key} unless @$window;
  }
}

=head2 add_custom_rule($rule_sub)

Add a custom sampling rule.

The rule subroutine receives ($exception, $event_data, $options, $current_result)
and should return a hash with sampling adjustments or undef.

=cut

sub add_custom_rule ($self, $rule_sub) {
  push @{$self->custom_rules}, $rule_sub;
  return $self;
}

1;

=head1 EXAMPLES

  # Basic usage
  my $sampler = Sentry::ErrorHandling::Sampling->new();
  my $result = $sampler->should_sample($exception, $event_data);
  
  if ($result->{should_sample}) {
    # Send to Sentry
  }
  
  # Custom sampling rule for specific errors
  $sampler->add_custom_rule(sub {
    my ($exception, $event_data, $options, $current_result) = @_;
    
    # Always sample payment-related errors
    if ($event_data->{contexts}{transaction}{type} eq 'payment') {
      return { sample_rate => 1.0, reason => 'payment_error' };
    }
    
    return undef;
  });

=head1 SEE ALSO

L<Sentry::ErrorHandling::Fingerprinting>, L<Sentry::ErrorHandling::Context>

=cut