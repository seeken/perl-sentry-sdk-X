package Sentry::ErrorHandling::Advanced;
use Mojo::Base -base, -signatures;

use Sentry::ErrorHandling::Fingerprinting;
use Sentry::ErrorHandling::Context;
use Sentry::ErrorHandling::Sampling;
use Sentry::ErrorHandling::Classification;
use Time::HiRes;

=head1 NAME

Sentry::ErrorHandling::Advanced - Comprehensive advanced error handling system

=head1 DESCRIPTION

Integrates fingerprinting, context enrichment, intelligent sampling, and 
classification to provide a complete advanced error handling solution.

=cut

# Component instances
has fingerprinter => sub { Sentry::ErrorHandling::Fingerprinting->new() };
has context_enricher => sub { Sentry::ErrorHandling::Context->new() };
has sampler => sub { Sentry::ErrorHandling::Sampling->new() };
has classifier => sub { Sentry::ErrorHandling::Classification->new() };

# Advanced error handling configuration
has config => sub { {
  # Enable/disable components
  enable_fingerprinting => 1,
  enable_context_enrichment => 1,
  enable_sampling => 1,
  enable_classification => 1,
  
  # Processing timeout
  processing_timeout => 10,
  
  # Error processing metrics
  collect_metrics => 1,
} };

# Processing metrics
has _metrics => sub { {
  errors_processed => 0,
  errors_sampled => 0,
  errors_dropped => 0,
  processing_time_total => 0,
  fingerprinting_time => 0,
  context_enrichment_time => 0,
  sampling_time => 0,
  classification_time => 0,
} };

=head2 process_error($exception, $event_data, $options)

Process an error through the complete advanced error handling pipeline.

Returns a processed event data structure or undef if the error should be dropped.

=cut

sub process_error ($self, $exception, $event_data, $options = {}) {
  my $start_time = Time::HiRes::time();
  
  eval {
    local $SIG{ALRM} = sub { die "Error processing timeout\n" };
    alarm $self->config->{processing_timeout};
    
    # Step 1: Sampling decision (early to avoid unnecessary processing)
    if ($self->config->{enable_sampling}) {
      my $sampling_start = Time::HiRes::time();
      my $sampling_result = $self->sampler->should_sample($exception, $event_data, $options);
      $self->_metrics->{sampling_time} += Time::HiRes::time() - $sampling_start;
      
      # Store sampling metadata
      $event_data->{extra}{sampling} = {
        sample_rate => $sampling_result->{sample_rate},
        reason => $sampling_result->{reason},
        metadata => $sampling_result->{metadata},
      };
      
      # Drop if not sampled
      if (!$sampling_result->{should_sample}) {
        $self->_metrics->{errors_dropped}++;
        alarm 0;
        return undef;
      }
    }
    
    # Step 2: Context enrichment
    if ($self->config->{enable_context_enrichment}) {
      my $context_start = Time::HiRes::time();
      $self->context_enricher->enrich_event($event_data, $exception, $options);
      $self->_metrics->{context_enrichment_time} += Time::HiRes::time() - $context_start;
    }
    
    # Step 3: Error classification
    if ($self->config->{enable_classification}) {
      my $classification_start = Time::HiRes::time();
      $self->classifier->classify_error($exception, $event_data, $options);
      $self->_metrics->{classification_time} += Time::HiRes::time() - $classification_start;
    }
    
    # Step 4: Fingerprinting (after classification for better accuracy)
    if ($self->config->{enable_fingerprinting}) {
      my $fingerprinting_start = Time::HiRes::time();
      
      my $fingerprint = $self->fingerprinter->generate_fingerprint($exception, $event_data);
      if ($fingerprint) {
        $event_data->{fingerprint} = [$fingerprint];
        $event_data->{extra}{fingerprinting} = {
          custom_fingerprint => $fingerprint,
          fingerprinting_version => '1.0',
        };
      }
      
      $self->_metrics->{fingerprinting_time} += Time::HiRes::time() - $fingerprinting_start;
    }
    
    # Step 5: Final enrichment and metadata
    $self->_add_processing_metadata($event_data, $start_time);
    
    alarm 0;
  };
  
  if ($@) {
    warn "Error in advanced error processing: $@";
    # Don't drop the error, but mark it as having processing issues
    $event_data->{extra}{error_processing} = {
      error => $@,
      processed_partially => 1,
    };
  }
  
  # Update metrics
  $self->_metrics->{errors_processed}++;
  $self->_metrics->{errors_sampled}++;
  $self->_metrics->{processing_time_total} += Time::HiRes::time() - $start_time;
  
  return $event_data;
}

=head2 configure_fingerprinting($config)

Configure the fingerprinting component.

=cut

sub configure_fingerprinting ($self, $config) {
  if ($config->{custom_rules}) {
    for my $rule (@{$config->{custom_rules}}) {
      $self->fingerprinter->add_custom_rule($rule);
    }
  }
  
  if ($config->{grouping_config}) {
    $self->fingerprinter->grouping_config({
      %{$self->fingerprinter->grouping_config},
      %{$config->{grouping_config}},
    });
  }
  
  return $self;
}

=head2 configure_context_enrichment($config)

Configure the context enrichment component.

=cut

sub configure_context_enrichment ($self, $config) {
  if ($config->{processors}) {
    for my $processor (@{$config->{processors}}) {
      $self->context_enricher->add_processor($processor);
    }
  }
  
  if ($config->{context_config}) {
    $self->context_enricher->config({
      %{$self->context_enricher->config},
      %{$config->{context_config}},
    });
  }
  
  return $self;
}

=head2 configure_sampling($config)

Configure the sampling component.

=cut

sub configure_sampling ($self, $config) {
  if ($config->{custom_rules}) {
    for my $rule (@{$config->{custom_rules}}) {
      $self->sampler->add_custom_rule($rule);
    }
  }
  
  if ($config->{sampling_config}) {
    $self->sampler->config({
      %{$self->sampler->config},
      %{$config->{sampling_config}},
    });
  }
  
  return $self;
}

=head2 configure_classification($config)

Configure the classification component.

=cut

sub configure_classification ($self, $config) {
  if ($config->{severity_patterns}) {
    my $current_patterns = $self->classifier->severity_patterns;
    for my $level (keys %{$config->{severity_patterns}}) {
      $current_patterns->{$level} = [
        @{$current_patterns->{$level} || []},
        @{$config->{severity_patterns}{$level}},
      ];
    }
  }
  
  if ($config->{category_patterns}) {
    my $current_patterns = $self->classifier->category_patterns;
    for my $category (keys %{$config->{category_patterns}}) {
      $current_patterns->{$category} = [
        @{$current_patterns->{$category} || []},
        @{$config->{category_patterns}{$category}},
      ];
    }
  }
  
  return $self;
}

=head2 get_processing_metrics()

Get error processing performance metrics.

=cut

sub get_processing_metrics ($self) {
  my $metrics = { %{$self->_metrics} };
  
  if ($metrics->{errors_processed} > 0) {
    $metrics->{average_processing_time} = 
        $metrics->{processing_time_total} / $metrics->{errors_processed};
    
    $metrics->{sampling_rate} = 
        $metrics->{errors_sampled} / $metrics->{errors_processed};
    
    $metrics->{drop_rate} = 
        $metrics->{errors_dropped} / $metrics->{errors_processed};
  }
  
  return $metrics;
}

=head2 reset_metrics()

Reset processing metrics counters.

=cut

sub reset_metrics ($self) {
  $self->_metrics->{$_} = 0 for keys %{$self->_metrics};
  return $self;
}

=head2 Helper methods

=cut

sub _add_processing_metadata ($self, $event_data, $start_time) {
  my $processing_time = Time::HiRes::time() - $start_time;
  
  $event_data->{extra}{advanced_processing} = {
    version => '1.0',
    processing_time => $processing_time,
    components_used => [
      $self->config->{enable_fingerprinting} ? 'fingerprinting' : (),
      $self->config->{enable_context_enrichment} ? 'context_enrichment' : (),
      $self->config->{enable_sampling} ? 'sampling' : (),
      $self->config->{enable_classification} ? 'classification' : (),
    ],
    processed_at => time(),
  };
  
  # Add component performance breakdown if metrics are enabled
  if ($self->config->{collect_metrics}) {
    $event_data->{extra}{advanced_processing}{performance} = {
      fingerprinting_time => $self->_metrics->{fingerprinting_time},
      context_enrichment_time => $self->_metrics->{context_enrichment_time},
      sampling_time => $self->_metrics->{sampling_time},
      classification_time => $self->_metrics->{classification_time},
    };
  }
}

=head2 Convenience methods for common configurations

=cut

sub configure_for_production ($self) {
  $self->configure_sampling({
    sampling_config => {
      base_sample_rate => 0.1,
      max_errors_per_minute => 50,
      burst_protection => { enabled => 1 },
      adaptive_sampling => { enabled => 1 },
    },
  });
  
  $self->configure_context_enrichment({
    context_config => {
      scrub_pii => 1,
      max_context_size => 32768,  # 32KB
    },
  });
  
  return $self;
}

sub configure_for_development ($self) {
  $self->configure_sampling({
    sampling_config => {
      base_sample_rate => 1.0,
      max_errors_per_minute => 1000,
      burst_protection => { enabled => 0 },
    },
  });
  
  $self->configure_context_enrichment({
    context_config => {
      scrub_pii => 0,
      max_context_size => 131072,  # 128KB
    },
  });
  
  return $self;
}

1;

=head1 EXAMPLES

  # Basic usage with all features enabled
  my $advanced_handler = Sentry::ErrorHandling::Advanced->new();
  
  # Process an error
  my $processed_event = $advanced_handler->process_error($exception, $event_data, {
    user_id => 12345,
    session_id => 'sess_abc123',
    priority => 'high',
  });
  
  if ($processed_event) {
    # Send to Sentry - error was sampled and processed
    $sentry_client->send_event($processed_event);
  }
  
  # Configure for production environment
  $advanced_handler->configure_for_production();
  
  # Add custom fingerprinting rule
  $advanced_handler->configure_fingerprinting({
    custom_rules => [
      sub {
        my ($exception, $event_data, $fingerprinter) = @_;
        
        # Custom rule for API integration errors
        if ($event_data->{tags}{error_category} eq 'integration') {
          my $api_name = $event_data->{contexts}{integration}{api_name} || 'unknown';
          return sha256_hex("api_integration:$api_name");
        }
        
        return undef;
      }
    ],
  });
  
  # Add custom context processor
  $advanced_handler->configure_context_enrichment({
    processors => [
      sub {
        my ($event_data, $exception, $options) = @_;
        
        # Add business context
        $event_data->{contexts}{business} = {
          customer_tier => $options->{customer_tier} || 'free',
          feature_flags => get_active_features($options->{user_id}),
          ab_tests => get_ab_test_assignments($options->{user_id}),
        };
      }
    ],
  });
  
  # Custom sampling rule for VIP customers
  $advanced_handler->configure_sampling({
    custom_rules => [
      sub {
        my ($exception, $event_data, $options, $current_result) = @_;
        
        # Always sample errors for VIP customers
        if ($options->{customer_tier} eq 'vip') {
          return { sample_rate => 1.0, reason => 'vip_customer' };
        }
        
        return undef;
      }
    ],
  });
  
  # Get processing metrics
  my $metrics = $advanced_handler->get_processing_metrics();
  say "Processed: $metrics->{errors_processed}";
  say "Sampled: $metrics->{errors_sampled}";  
  say "Dropped: $metrics->{errors_dropped}";
  say "Average processing time: $metrics->{average_processing_time}ms";

=head1 SEE ALSO

L<Sentry::ErrorHandling::Fingerprinting>, L<Sentry::ErrorHandling::Context>, 
L<Sentry::ErrorHandling::Sampling>, L<Sentry::ErrorHandling::Classification>

=cut