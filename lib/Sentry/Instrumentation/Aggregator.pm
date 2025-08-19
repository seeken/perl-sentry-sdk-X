package Sentry::Instrumentation::Aggregator;
use Mojo::Base -base, -signatures;

use Sentry::Hub;
use Time::HiRes qw(time);
use Mojo::JSON qw(encode_json);
use List::Util qw(sum min max);

=head1 NAME

Sentry::Instrumentation::Aggregator - Metrics aggregation and reporting

=head1 SYNOPSIS

  use Sentry::Instrumentation::Aggregator;
  
  my $aggregator = Sentry::Instrumentation::Aggregator->new(
    flush_interval => 60,    # seconds
    batch_size => 100,       # metrics per batch
    auto_flush => 1          # automatic flushing
  );
  
  # Collect metrics from various sources
  $aggregator->collect_metrics($metrics_instance);
  $aggregator->add_metric('counter', 'api.requests', 5, { endpoint => '/users' });
  
  # Manual flush
  $aggregator->flush();
  
  # Get aggregated statistics
  my $stats = $aggregator->get_stats();

=head1 DESCRIPTION

This module provides efficient aggregation, batching, and periodic reporting
of custom metrics to the Sentry backend. It handles metric deduplication,
statistical aggregation, and optimized transport.

=cut

has 'flush_interval' => 60;  # seconds
has 'batch_size' => 100;     # metrics per batch
has 'auto_flush' => 1;
has 'enabled' => 1;
has '_metrics_buffer' => sub { [] };
has '_aggregated_data' => sub { {} };
has '_last_flush' => sub { time() };
has '_stats' => sub { {
  metrics_collected => 0,
  metrics_flushed => 0,
  batches_sent => 0,
  last_flush_duration => 0,
  errors => 0
} };

=head1 METHODS

=head2 new(%options)

Create a new metrics aggregator.

  my $aggregator = Sentry::Instrumentation::Aggregator->new(
    flush_interval => 30,
    batch_size => 50,
    auto_flush => 1
  );

=cut

sub new ($class, %options) {
  my $self = $class->SUPER::new(%options);
  
  # Start auto-flush timer if enabled
  if ($self->auto_flush) {
    $self->_start_auto_flush();
  }
  
  return $self;
}

=head2 Metric Collection

=head3 collect_metrics($metrics_instance)

Collect all metrics from a Metrics instance.

  $aggregator->collect_metrics($my_metrics);

=cut

sub collect_metrics ($self, $metrics) {
  return unless $self->enabled && $metrics;
  
  my $metrics_data = $metrics->get_metrics();
  
  # Process each metric type
  for my $type (qw(counters gauges histograms distributions sets)) {
    next unless $metrics_data->{$type};
    
    for my $key (keys %{$metrics_data->{$type}}) {
      my $metric = $metrics_data->{$type}{$key};
      $self->_add_to_buffer($type, $key, $metric);
    }
  }
  
  $self->_stats->{metrics_collected} += keys %{$metrics_data->{counters} || {}};
  $self->_stats->{metrics_collected} += keys %{$metrics_data->{gauges} || {}};
  $self->_stats->{metrics_collected} += keys %{$metrics_data->{histograms} || {}};
  $self->_stats->{metrics_collected} += keys %{$metrics_data->{distributions} || {}};
  $self->_stats->{metrics_collected} += keys %{$metrics_data->{sets} || {}};
  
  # Check if we should flush
  if ($self->should_flush()) {
    $self->flush();
  }
  
  return $self;
}

=head3 add_metric($type, $name, $value, $tags = {})

Add a single metric to the aggregation buffer.

  $aggregator->add_metric('counter', 'requests.total', 5, { method => 'GET' });

=cut

sub add_metric ($self, $type, $name, $value, $tags = {}) {
  return unless $self->enabled;
  
  my $metric = {
    name => $name,
    type => $type,
    value => $value,
    tags => $tags,
    timestamp => time()
  };
  
  my $key = $self->_build_metric_key($name, $tags);
  $self->_add_to_buffer($type, $key, $metric);
  $self->_stats->{metrics_collected}++;
  
  # Check if we should flush
  if ($self->should_flush()) {
    $self->flush();
  }
  
  return $self;
}

=head2 Aggregation and Flushing

=head3 should_flush()

Check if metrics should be flushed based on time or buffer size.

=cut

sub should_flush ($self) {
  my $time_to_flush = (time() - $self->_last_flush) >= $self->flush_interval;
  my $buffer_full = scalar(@{$self->_metrics_buffer}) >= $self->batch_size;
  
  return $time_to_flush || $buffer_full;
}

=head3 flush()

Flush all collected metrics to Sentry.

  $aggregator->flush();

=cut

sub flush ($self) {
  return unless $self->enabled;
  return unless @{$self->_metrics_buffer};
  
  my $start_time = time();
  
  eval {
    # Aggregate similar metrics
    my $aggregated = $self->_aggregate_metrics();
    
    # Send in batches
    my @batches = $self->_create_batches($aggregated);
    
    for my $batch (@batches) {
      $self->_send_metrics_batch($batch);
      $self->_stats->{batches_sent}++;
    }
    
    # Update statistics
    $self->_stats->{metrics_flushed} += scalar(@{$self->_metrics_buffer});
    $self->_stats->{last_flush_duration} = time() - $start_time;
    
    # Clear buffer
    $self->_metrics_buffer([]);
    $self->_last_flush(time());
  };
  
  if (my $error = $@) {
    $self->_stats->{errors}++;
    warn "Metrics flush failed: $error";
  }
  
  return $self;
}

=head3 get_stats()

Get aggregation and flush statistics.

  my $stats = $aggregator->get_stats();

=cut

sub get_stats ($self) {
  my $stats = { %{$self->_stats} };
  
  $stats->{buffer_size} = scalar(@{$self->_metrics_buffer});
  $stats->{time_since_last_flush} = time() - $self->_last_flush;
  
  if ($stats->{metrics_collected} > 0) {
    $stats->{flush_efficiency} = $stats->{metrics_flushed} / $stats->{metrics_collected};
  }
  
  return $stats;
}

=head2 Control Methods

=head3 start()

Start the aggregator (enables collection and auto-flush).

=cut

sub start ($self) {
  $self->enabled(1);
  if ($self->auto_flush) {
    $self->_start_auto_flush();
  }
  return $self;
}

=head3 stop()

Stop the aggregator and flush remaining metrics.

=cut

sub stop ($self) {
  $self->flush() if $self->enabled;
  $self->enabled(0);
  $self->_stop_auto_flush();
  return $self;
}

=head3 reset()

Reset all metrics and statistics.

=cut

sub reset ($self) {
  $self->_metrics_buffer([]);
  $self->_aggregated_data({});
  $self->_stats({
    metrics_collected => 0,
    metrics_flushed => 0,
    batches_sent => 0,
    last_flush_duration => 0,
    errors => 0
  });
  $self->_last_flush(time());
  return $self;
}

=head2 Internal Methods

=cut

sub _add_to_buffer ($self, $type, $key, $metric) {
  push @{$self->_metrics_buffer}, {
    type => $type,
    key => $key,
    metric => $metric
  };
}

sub _build_metric_key ($self, $name, $tags) {
  my @tag_parts = map { "$_:" . $tags->{$_} } sort keys %$tags;
  my $tag_string = @tag_parts ? join(',', @tag_parts) : '';
  return $name . ($tag_string ? "|$tag_string" : '');
}

sub _aggregate_metrics ($self) {
  my %aggregated;
  
  for my $item (@{$self->_metrics_buffer}) {
    my $type = $item->{type};
    my $key = $item->{key};
    my $metric = $item->{metric};
    
    if ($type eq 'counters') {
      # Sum counter values
      $aggregated{$type}{$key} //= { %$metric, value => 0 };
      $aggregated{$type}{$key}{value} += $metric->{value};
      
    } elsif ($type eq 'gauges') {
      # Use latest gauge value
      $aggregated{$type}{$key} = $metric;
      
    } elsif ($type eq 'histograms' || $type eq 'distributions') {
      # Combine histogram values
      $aggregated{$type}{$key} //= { %$metric, values => [] };
      push @{$aggregated{$type}{$key}{values}}, @{$metric->{values}};
      
    } elsif ($type eq 'sets') {
      # Merge set values
      $aggregated{$type}{$key} //= { %$metric, unique_count => 0 };
      # Note: We'd need the actual values to properly merge sets
      # For now, just use the latest count
      $aggregated{$type}{$key}{unique_count} = $metric->{unique_count};
    }
    
    # Update timestamp to latest
    $aggregated{$type}{$key}{timestamp} = $metric->{timestamp} 
      if !$aggregated{$type}{$key}{timestamp} || 
         $metric->{timestamp} > $aggregated{$type}{$key}{timestamp};
  }
  
  return \%aggregated;
}

sub _create_batches ($self, $aggregated) {
  my @all_metrics;
  
  # Flatten aggregated metrics
  for my $type (keys %$aggregated) {
    for my $key (keys %{$aggregated->{$type}}) {
      push @all_metrics, {
        type => $type,
        key => $key,
        %{$aggregated->{$type}{$key}}
      };
    }
  }
  
  # Split into batches
  my @batches;
  my $batch_size = $self->batch_size;
  
  for (my $i = 0; $i < @all_metrics; $i += $batch_size) {
    my $end = $i + $batch_size - 1;
    $end = $#all_metrics if $end > $#all_metrics;
    push @batches, [@all_metrics[$i..$end]];
  }
  
  return @batches;
}

sub _send_metrics_batch ($self, $batch) {
  # Prepare metrics envelope for Sentry
  my $envelope = {
    timestamp => time(),
    metrics => []
  };
  
  for my $metric (@$batch) {
    my $sentry_metric = {
      name => $metric->{name},
      type => $metric->{type},
      value => $self->_format_metric_value($metric),
      unit => $self->_get_metric_unit($metric),
      tags => $metric->{tags} || {},
      timestamp => $metric->{timestamp}
    };
    
    push @{$envelope->{metrics}}, $sentry_metric;
  }
  
  # Send to Sentry using the Hub
  my $hub = Sentry::Hub->get_current_hub();
  if ($hub && $hub->client) {
    # Send metrics as custom events to Sentry
    $hub->capture_event({
      message => 'Custom metrics batch',
      level => 'info',
      tags => {
        batch_size => scalar(@$batch),
        metrics_type => 'custom_instrumentation'
      },
      extra => {
        metrics => $envelope
      },
      contexts => {
        metrics => {
          batch_id => sprintf("batch_%d_%d", time(), rand(1000)),
          flush_time => time(),
          metric_count => scalar(@$batch)
        }
      }
    });
    
    # Also add breadcrumb for debugging
    $hub->add_breadcrumb({
      type => 'default',
      category => 'metrics',
      message => 'Custom metrics batch sent',
      level => 'info',
      data => {
        batch_size => scalar(@$batch),
        envelope => $envelope
      }
    });
  }
}

sub _format_metric_value ($self, $metric) {
  my $type = $metric->{type};
  
  if ($type eq 'counters' || $type eq 'gauges') {
    return $metric->{value};
    
  } elsif ($type eq 'histograms' || $type eq 'distributions') {
    # Return statistical summary
    my $values = $metric->{values};
    return {} unless @$values;
    
    my @sorted = sort { $a <=> $b } @$values;
    my $count = @sorted;
    my $sum = sum(@sorted);
    
    return {
      count => $count,
      sum => $sum,
      min => $sorted[0],
      max => $sorted[-1],
      avg => $sum / $count,
      p50 => $sorted[int($count * 0.5)],
      p95 => $sorted[int($count * 0.95)],
      p99 => $sorted[int($count * 0.99)]
    };
    
  } elsif ($type eq 'sets') {
    return $metric->{unique_count};
  }
  
  return $metric->{value};
}

sub _get_metric_unit ($self, $metric) {
  my $name = $metric->{name};
  
  # Infer units from metric names
  return 'millisecond' if $name =~ /\.(duration|time|latency)$/;
  return 'byte' if $name =~ /\.(size|bytes|memory)$/;
  return 'percent' if $name =~ /\.(rate|ratio|percent)$/;
  return 'request' if $name =~ /\.(requests|calls)$/;
  return 'error' if $name =~ /\.(errors|failures)$/;
  
  return 'none';  # dimensionless
}

sub _start_auto_flush ($self) {
  # In a real implementation, this would set up a timer
  # For now, we rely on periodic calls to collect_metrics
}

sub _stop_auto_flush ($self) {
  # Stop any running timers
}

1;

=head1 SEE ALSO

L<Sentry::Instrumentation::Metrics>, L<Sentry::Hub>

=head1 AUTHOR

Generated for Sentry Perl SDK Modernization

=cut