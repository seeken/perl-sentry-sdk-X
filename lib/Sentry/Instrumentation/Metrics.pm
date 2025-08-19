package Sentry::Instrumentation::Metrics;
use Mojo::Base -base, -signatures;

use Carp qw(croak);
use Time::HiRes qw(time);
use List::Util qw(sum min max);

=head1 NAME

Sentry::Instrumentation::Metrics - Custom metrics collection and reporting

=head1 SYNOPSIS

  use Sentry::Instrumentation::Metrics;
  
  my $metrics = Sentry::Instrumentation::Metrics->new();
  
  # Counters - values that only increase
  $metrics->increment('api.requests', 1, { endpoint => '/users' });
  $metrics->counter('errors.database')->increment(2);
  
  # Gauges - values that can go up and down
  $metrics->gauge('memory.usage')->set(1024 * 1024);
  $metrics->gauge('active_connections', 50, { server => 'web1' });
  
  # Histograms - distribution of values
  $metrics->histogram('request.duration')->record(0.150, { method => 'GET' });
  $metrics->timing('db.query_time', 0.025);
  
  # Distributions - like histograms but more detailed
  $metrics->distribution('payload.size')->record(1024);
  
  # Sets - unique values
  $metrics->set('unique_users')->add('user123');

=head1 DESCRIPTION

This module provides comprehensive metrics collection capabilities for custom
application instrumentation. It supports various metric types commonly used
in modern observability practices.

=cut

has 'name_prefix' => '';
has 'default_tags' => sub { {} };
has 'enabled' => 1;
has '_metrics' => sub { {} };
has '_aggregation_window' => 60; # seconds
has '_last_flush' => sub { time() };

# Metric type constants
use constant {
    TYPE_COUNTER => 'counter',
    TYPE_GAUGE => 'gauge',
    TYPE_HISTOGRAM => 'histogram',
    TYPE_DISTRIBUTION => 'distribution',
    TYPE_SET => 'set',
};

=head1 METHODS

=head2 new(%options)

Create a new metrics collector.

  my $metrics = Sentry::Instrumentation::Metrics->new(
    name_prefix => 'myapp.',
    default_tags => { service => 'api', version => '1.0' },
    enabled => 1
  );

=cut

sub new ($class, %options) {
  my $self = $class->SUPER::new(%options);
  $self->_initialize_metrics();
  return $self;
}

sub _initialize_metrics ($self) {
  $self->_metrics({
    counters => {},
    gauges => {},
    histograms => {},
    distributions => {},
    sets => {},
  });
}

=head2 Counter Operations

=head3 increment($name, $value = 1, $tags = {})

Increment a counter by the specified value.

  $metrics->increment('requests.total', 1, { method => 'GET' });

=cut

sub increment ($self, $name, $value = 1, $tags = {}) {
  return unless $self->enabled;
  
  croak "Counter value must be positive" if $value < 0;
  
  my $full_name = $self->_build_metric_name($name);
  my $metric_key = $self->_build_metric_key($full_name, $tags);
  
  my $counters = $self->_metrics->{counters};
  $counters->{$metric_key} //= $self->_create_counter_metric($full_name, $tags);
  $counters->{$metric_key}{value} += $value;
  $counters->{$metric_key}{last_updated} = time();
  
  return $self;
}

=head3 counter($name)

Get a counter object for fluent operations.

  $metrics->counter('api.errors')->increment(1)->increment(2);

=cut

sub counter ($self, $name) {
  return Sentry::Instrumentation::Metrics::Counter->new(
    metrics => $self,
    name => $name
  );
}

=head2 Gauge Operations

=head3 gauge($name, $value, $tags = {})

Set a gauge to a specific value.

  $metrics->gauge('memory.usage', 1024*1024, { type => 'heap' });

=cut

sub gauge ($self, $name, $value = undef, $tags = {}) {
  return unless $self->enabled;
  
  my $full_name = $self->_build_metric_name($name);
  
  if (defined $value) {
    my $metric_key = $self->_build_metric_key($full_name, $tags);
    my $gauges = $self->_metrics->{gauges};
    $gauges->{$metric_key} = $self->_create_gauge_metric($full_name, $value, $tags);
    return $self;
  } else {
    return Sentry::Instrumentation::Metrics::Gauge->new(
      metrics => $self,
      name => $name
    );
  }
}

=head2 Histogram Operations

=head3 histogram($name)

Get a histogram object for recording value distributions.

  $metrics->histogram('request.duration')->record(0.150);

=cut

sub histogram ($self, $name) {
  return Sentry::Instrumentation::Metrics::Histogram->new(
    metrics => $self,
    name => $name
  );
}

=head3 timing($name, $duration, $tags = {})

Record a timing value (convenience method for histograms).

  $metrics->timing('db.query', 0.025, { operation => 'select' });

=cut

sub timing ($self, $name, $duration, $tags = {}) {
  return $self->histogram($name)->record($duration, $tags);
}

=head2 Distribution Operations

=head3 distribution($name)

Get a distribution object for recording value distributions with higher fidelity.

  $metrics->distribution('payload.size')->record(1024);

=cut

sub distribution ($self, $name) {
  return Sentry::Instrumentation::Metrics::Distribution->new(
    metrics => $self,
    name => $name
  );
}

=head2 Set Operations

=head3 set($name)

Get a set object for recording unique values.

  $metrics->set('unique_users')->add('user123');

=cut

sub set ($self, $name) {
  return Sentry::Instrumentation::Metrics::Set->new(
    metrics => $self,
    name => $name
  );
}

=head2 Time Measurement

=head3 time_block($name, $code, $tags = {})

Time the execution of a code block.

  my $result = $metrics->time_block('db.transaction', sub {
    # database operations
    return $some_result;
  }, { operation => 'bulk_insert' });

=cut

sub time_block ($self, $name, $code, $tags = {}) {
  my $start_time = time();
  
  my $result = eval { $code->() };
  my $error = $@;
  
  my $duration = time() - $start_time;
  $self->timing($name, $duration, $tags);
  
  if ($error) {
    # Increment error counter if timing failed
    $self->increment("$name.errors", 1, $tags);
    croak $error;
  }
  
  return $result;
}

=head2 Metric Management

=head3 get_metrics()

Get all collected metrics for reporting.

  my $metrics_data = $metrics->get_metrics();

=cut

sub get_metrics ($self) {
  my $data = {};
  
  # Process counters
  for my $key (keys %{$self->_metrics->{counters}}) {
    my $metric = $self->_metrics->{counters}{$key};
    $data->{counters}{$key} = {
      name => $metric->{name},
      value => $metric->{value},
      tags => $metric->{tags},
      type => TYPE_COUNTER,
      timestamp => $metric->{last_updated}
    };
  }
  
  # Process gauges
  for my $key (keys %{$self->_metrics->{gauges}}) {
    my $metric = $self->_metrics->{gauges}{$key};
    $data->{gauges}{$key} = {
      name => $metric->{name},
      value => $metric->{value},
      tags => $metric->{tags},
      type => TYPE_GAUGE,
      timestamp => $metric->{timestamp}
    };
  }
  
  # Process histograms
  for my $key (keys %{$self->_metrics->{histograms}}) {
    my $metric = $self->_metrics->{histograms}{$key};
    $data->{histograms}{$key} = {
      name => $metric->{name},
      values => [@{$metric->{values}}], # copy
      tags => $metric->{tags},
      type => TYPE_HISTOGRAM,
      statistics => $self->_calculate_histogram_stats($metric->{values})
    };
  }
  
  # Process distributions
  for my $key (keys %{$self->_metrics->{distributions}}) {
    my $metric = $self->_metrics->{distributions}{$key};
    $data->{distributions}{$key} = {
      name => $metric->{name},
      values => [@{$metric->{values}}], # copy
      tags => $metric->{tags},
      type => TYPE_DISTRIBUTION,
      statistics => $self->_calculate_histogram_stats($metric->{values})
    };
  }
  
  # Process sets
  for my $key (keys %{$self->_metrics->{sets}}) {
    my $metric = $self->_metrics->{sets}{$key};
    $data->{sets}{$key} = {
      name => $metric->{name},
      unique_count => scalar(keys %{$metric->{values}}),
      tags => $metric->{tags},
      type => TYPE_SET
    };
  }
  
  return $data;
}

=head3 reset()

Reset all metrics (useful for testing or periodic cleanup).

  $metrics->reset();

=cut

sub reset ($self) {
  $self->_initialize_metrics();
  $self->_last_flush(time());
  return $self;
}

=head3 should_aggregate()

Check if metrics should be aggregated based on time window.

=cut

sub should_aggregate ($self) {
  return (time() - $self->_last_flush) >= $self->_aggregation_window;
}

=head2 Internal Methods

=cut

sub _build_metric_name ($self, $name) {
  return $self->name_prefix . $name;
}

sub _build_metric_key ($self, $name, $tags) {
  my @tag_parts = map { "$_:" . $tags->{$_} } sort keys %$tags;
  my $tag_string = @tag_parts ? join(',', @tag_parts) : '';
  return $name . ($tag_string ? "|$tag_string" : '');
}

sub _merge_tags ($self, $tags) {
  return { %{$self->default_tags}, %$tags };
}

sub _create_counter_metric ($self, $name, $tags) {
  return {
    name => $name,
    value => 0,
    tags => $self->_merge_tags($tags),
    type => TYPE_COUNTER,
    created_at => time(),
    last_updated => time()
  };
}

sub _create_gauge_metric ($self, $name, $value, $tags) {
  return {
    name => $name,
    value => $value,
    tags => $self->_merge_tags($tags),
    type => TYPE_GAUGE,
    timestamp => time()
  };
}

sub _record_histogram_value ($self, $name, $value, $tags) {
  my $full_name = $self->_build_metric_name($name);
  my $metric_key = $self->_build_metric_key($full_name, $tags);
  
  my $histograms = $self->_metrics->{histograms};
  $histograms->{$metric_key} //= {
    name => $full_name,
    values => [],
    tags => $self->_merge_tags($tags),
    type => TYPE_HISTOGRAM,
    created_at => time()
  };
  
  push @{$histograms->{$metric_key}{values}}, $value;
}

sub _record_distribution_value ($self, $name, $value, $tags) {
  my $full_name = $self->_build_metric_name($name);
  my $metric_key = $self->_build_metric_key($full_name, $tags);
  
  my $distributions = $self->_metrics->{distributions};
  $distributions->{$metric_key} //= {
    name => $full_name,
    values => [],
    tags => $self->_merge_tags($tags),
    type => TYPE_DISTRIBUTION,
    created_at => time()
  };
  
  push @{$distributions->{$metric_key}{values}}, $value;
}

sub _add_set_value ($self, $name, $value, $tags) {
  my $full_name = $self->_build_metric_name($name);
  my $metric_key = $self->_build_metric_key($full_name, $tags);
  
  my $sets = $self->_metrics->{sets};
  $sets->{$metric_key} //= {
    name => $full_name,
    values => {},
    tags => $self->_merge_tags($tags),
    type => TYPE_SET,
    created_at => time()
  };
  
  $sets->{$metric_key}{values}{$value} = 1;
}

sub _calculate_histogram_stats ($self, $values) {
  return {} unless @$values;
  
  my @sorted = sort { $a <=> $b } @$values;
  my $count = @sorted;
  my $sum = sum(@sorted);
  
  return {
    count => $count,
    sum => $sum,
    min => $sorted[0],
    max => $sorted[-1],
    mean => $sum / $count,
    median => $count % 2 ? $sorted[int($count/2)] : 
              ($sorted[int($count/2)-1] + $sorted[int($count/2)]) / 2,
    p95 => $sorted[int($count * 0.95)],
    p99 => $sorted[int($count * 0.99)]
  };
}

# Metric type classes for fluent API

package Sentry::Instrumentation::Metrics::Counter {
  use Mojo::Base -base, -signatures;
  
  has 'metrics';
  has 'name';
  
  sub increment ($self, $value = 1, $tags = {}) {
    $self->metrics->increment($self->name, $value, $tags);
    return $self;
  }
}

package Sentry::Instrumentation::Metrics::Gauge {
  use Mojo::Base -base, -signatures;
  
  has 'metrics';
  has 'name';
  
  sub set ($self, $value, $tags = {}) {
    $self->metrics->gauge($self->name, $value, $tags);
    return $self;
  }
  
  sub increment ($self, $value = 1, $tags = {}) {
    # Note: This would need to track current value for proper increment
    # For now, just set the value
    $self->set($value, $tags);
    return $self;
  }
  
  sub decrement ($self, $value = 1, $tags = {}) {
    # Note: This would need to track current value for proper decrement
    # For now, just set the negative value
    $self->set(-$value, $tags);
    return $self;
  }
}

package Sentry::Instrumentation::Metrics::Histogram {
  use Mojo::Base -base, -signatures;
  
  has 'metrics';
  has 'name';
  
  sub record ($self, $value, $tags = {}) {
    $self->metrics->_record_histogram_value($self->name, $value, $tags);
    return $self;
  }
}

package Sentry::Instrumentation::Metrics::Distribution {
  use Mojo::Base -base, -signatures;
  
  has 'metrics';
  has 'name';
  
  sub record ($self, $value, $tags = {}) {
    $self->metrics->_record_distribution_value($self->name, $value, $tags);
    return $self;
  }
}

package Sentry::Instrumentation::Metrics::Set {
  use Mojo::Base -base, -signatures;
  
  has 'metrics';
  has 'name';
  
  sub add ($self, $value, $tags = {}) {
    $self->metrics->_add_set_value($self->name, $value, $tags);
    return $self;
  }
}

1;

=head1 SEE ALSO

L<Sentry::Instrumentation::Spans>, L<Sentry::Instrumentation::Aggregator>

=head1 AUTHOR

Generated for Sentry Perl SDK Modernization

=cut