#!/usr/bin/env perl
use strict;
use warnings;
use lib './lib';

use Sentry::ErrorHandling::Advanced;
use Sentry::ErrorHandling::Fingerprinting;
use Sentry::ErrorHandling::Context;
use Sentry::ErrorHandling::Sampling;
use Sentry::ErrorHandling::Classification;

use Data::Dumper;
use Time::HiRes qw(sleep);
use Digest::SHA qw(sha256_hex);

=head1 NAME

phase3_demo.pl - Comprehensive demo of Phase 3 Advanced Error Handling

=head1 DESCRIPTION

Demonstrates all Phase 3 features:
- Error fingerprinting and grouping
- Enhanced context enrichment 
- Intelligent sampling strategies
- Advanced error classification
- Integrated advanced error processing

=cut

print "🎯 Phase 3: Advanced Error Handling Demo\n";
print "=" x 50, "\n\n";

# Initialize the advanced error handler
my $advanced_handler = Sentry::ErrorHandling::Advanced->new();

# Configure for demo environment (verbose logging)
$advanced_handler->config->{collect_metrics} = 1;

print "1. 🔍 ERROR FINGERPRINTING DEMO\n";
print "-" x 30, "\n";

my $fingerprinter = $advanced_handler->fingerprinter;

# Demo 1: Stack trace based fingerprinting
print "Demo 1a: Stack trace based fingerprinting\n";
my $mojo_exception = eval {
  require Mojo::Exception;
  Mojo::Exception->new("Database connection failed")->trace;
};

my $event_data_1 = {
  exception => {
    values => [{
      type => 'Mojo::Exception',
      value => 'Database connection failed',
      stacktrace => {
        frames => [
          { filename => 'MyApp/Database.pm', lineno => 42, function => 'connect' },
          { filename => 'MyApp/Controller.pm', lineno => 123, function => 'handle_request' },
          { filename => 'MyApp.pm', lineno => 89, function => 'dispatch' },
        ]
      }
    }]
  }
};

my $fingerprint_1 = $fingerprinter->generate_fingerprint($mojo_exception, $event_data_1);
print "  Fingerprint 1: $fingerprint_1\n";

# Similar error with slight variation
my $event_data_2 = {
  exception => {
    values => [{
      type => 'Mojo::Exception', 
      value => 'Database connection timeout',  # Different message
      stacktrace => {
        frames => [
          { filename => 'MyApp/Database.pm', lineno => 42, function => 'connect' }, # Same location
          { filename => 'MyApp/Controller.pm', lineno => 123, function => 'handle_request' },
          { filename => 'MyApp.pm', lineno => 89, function => 'dispatch' },
        ]
      }
    }]
  }
};

my $fingerprint_2 = $fingerprinter->generate_fingerprint(undef, $event_data_2);
print "  Fingerprint 2: $fingerprint_2\n";
print "  Same fingerprint? " . ($fingerprint_1 eq $fingerprint_2 ? "YES ✓" : "NO ✗") . "\n\n";

# Demo 1b: Custom fingerprinting rules
print "Demo 1b: Custom fingerprinting rules\n";
$fingerprinter->add_custom_rule(sub {
  my ($exception, $event_data, $fp) = @_;
  
  # Custom rule for payment errors
  if ($event_data->{contexts}{transaction}{type} eq 'payment') {
    my $payment_method = $event_data->{contexts}{transaction}{payment_method} || 'unknown';
    return sha256_hex("payment_error:$payment_method");
  }
  
  return undef;
});

my $payment_event = {
  exception => {
    values => [{ type => 'PaymentError', value => 'Credit card declined' }]
  },
  contexts => {
    transaction => {
      type => 'payment',
      payment_method => 'credit_card',
    }
  }
};

my $payment_fingerprint = $fingerprinter->generate_fingerprint(undef, $payment_event);
print "  Payment error fingerprint: $payment_fingerprint\n\n";

print "2. 📊 CONTEXT ENRICHMENT DEMO\n";
print "-" x 30, "\n";

my $context_enricher = $advanced_handler->context_enricher;

# Demo 2a: Automatic context collection
print "Demo 2a: Automatic context collection\n";
my $context_event = {
  message => 'Test error for context demo'
};

$context_enricher->enrich_event($context_event, undef, {
  user_id => 'user_12345',
  user_email => 'john@example.com',
  session_id => 'sess_abcdef',
  request_method => 'POST',
  request_uri => '/api/users/create',
  request_start_time => time() - 2.5,  # 2.5 seconds ago
});

print "  Enriched contexts:\n";
for my $context_name (sort keys %{$context_event->{contexts}}) {
  print "    - $context_name: " . (scalar keys %{$context_event->{contexts}{$context_name}}) . " fields\n";
}
print "\n";

# Demo 2b: Custom context processors
print "Demo 2b: Custom context processors\n";
$context_enricher->add_processor(sub {
  my ($event_data, $exception, $options) = @_;
  
  # Add application-specific context
  $event_data->{contexts}{application} = {
    version => '2.1.0',
    deployment => 'staging',
    feature_flags => {
      new_ui => 1,
      beta_features => 0,
    },
    ab_tests => {
      checkout_flow => 'variant_b',
    }
  };
  
  # Add business context
  $event_data->{contexts}{business} = {
    customer_tier => $options->{customer_tier} || 'standard',
    subscription_active => $options->{subscription_active} // 1,
    last_payment_date => '2024-01-15',
  };
});

my $custom_context_event = { message => 'Business logic error' };
$context_enricher->enrich_event($custom_context_event, undef, {
  customer_tier => 'premium',
  subscription_active => 1,
});

print "  Custom contexts added:\n";
print "    - Application version: " . $custom_context_event->{contexts}{application}{version} . "\n";
print "    - Customer tier: " . $custom_context_event->{contexts}{business}{customer_tier} . "\n\n";

print "3. 🎲 INTELLIGENT SAMPLING DEMO\n";
print "-" x 30, "\n";

my $sampler = $advanced_handler->sampler;

# Demo 3a: Priority-based sampling
print "Demo 3a: Priority-based sampling\n";
for my $priority (qw(critical high medium low)) {
  my $sample_result = $sampler->should_sample(undef, { level => 'error' }, { priority => $priority });
  printf "  %s priority: %.0f%% sample rate (%s)\n", 
         ucfirst($priority), 
         $sample_result->{sample_rate} * 100,
         $sample_result->{should_sample} ? 'SAMPLED' : 'DROPPED';
}
print "\n";

# Demo 3b: Error type-based sampling
print "Demo 3b: Error type-based sampling\n";
my @error_types = ('DBI::Exception', 'Mojo::Exception', 'die', 'warn');
for my $error_type (@error_types) {
  my $test_event = { 
    exception => { values => [{ type => $error_type }] }
  };
  my $sample_result = $sampler->should_sample(undef, $test_event);
  printf "  %-15s: %.0f%% sample rate\n", 
         $error_type, 
         $sample_result->{sample_rate} * 100;
}
print "\n";

# Demo 3c: Frequency-based sampling
print "Demo 3c: Frequency-based sampling simulation\n";
my $frequent_error = "Frequent database timeout";
print "  Simulating frequent error occurrence...\n";

for my $i (1..10) {
  my $sample_result = $sampler->should_sample($frequent_error, { message => $frequent_error });
  printf "    Error #%d: %.0f%% rate (%s) - %s\n", 
         $i,
         $sample_result->{sample_rate} * 100,
         $sample_result->{should_sample} ? 'SAMPLED' : 'DROPPED',
         $sample_result->{reason};
  
  sleep 0.1;  # Small delay to simulate real timing
}
print "\n";

# Demo 3d: Custom sampling rules
print "Demo 3d: Custom sampling rules\n";
$sampler->add_custom_rule(sub {
  my ($exception, $event_data, $options, $current_result) = @_;
  
  # Always sample errors from VIP customers
  if ($options->{customer_tier} eq 'vip') {
    return { sample_rate => 1.0, reason => 'vip_customer' };
  }
  
  # Sample API errors at higher rate
  if ($event_data->{contexts}{request}{url} && $event_data->{contexts}{request}{url} =~ /\/api\//) {
    return { sample_rate => 0.8, reason => 'api_endpoint' };
  }
  
  return undef;
});

my $vip_result = $sampler->should_sample(undef, {}, { customer_tier => 'vip' });
print "  VIP customer error: " . ($vip_result->{should_sample} ? "ALWAYS SAMPLED" : "dropped") . " - " . $vip_result->{reason} . "\n\n";

print "4. 🏷️  ERROR CLASSIFICATION DEMO\n";
print "-" x 30, "\n";

my $classifier = $advanced_handler->classifier;

# Demo 4a: Severity classification
print "Demo 4a: Automatic severity classification\n";
my @test_errors = (
  "Payment processing failed - credit card declined",
  "Database connection timeout - retrying",
  "Slow query detected: SELECT * FROM large_table took 5.2s", 
  "User login attempt with invalid password",
  "Cache miss for key 'user_preferences_123'",
);

for my $error (@test_errors) {
  my $class_event = { 
    message => $error,
    level => 'error'  # Start with default level
  };
  
  $classifier->classify_error($error, $class_event);
  
  printf "  %-50s -> %s\n", 
         substr($error, 0, 45) . (length($error) > 45 ? "..." : ""),
         uc($class_event->{level});
}
print "\n";

# Demo 4b: Category classification  
print "Demo 4b: Error category classification\n";
my @categorize_errors = (
  "DBI connect failed: Access denied for user",
  "HTTP request timeout to external API",  
  "Invalid user credentials provided",
  "Business rule violation: insufficient account balance",
  "Memory usage exceeded 90% threshold",
);

for my $error (@categorize_errors) {
  my $cat_event = { message => $error };
  $classifier->classify_error($error, $cat_event);
  
  my $category = $cat_event->{tags}{error_category} || 'uncategorized';
  printf "  %-40s -> %s\n",
         substr($error, 0, 35) . (length($error) > 35 ? "..." : ""),
         $category;
}
print "\n";

# Demo 4c: Business impact classification
print "Demo 4c: Business impact classification\n";
my @impact_errors = (
  "Payment gateway error during checkout",
  "User registration email failed to send", 
  "Analytics data collection timeout",
);

for my $error (@impact_errors) {
  my $impact_event = { message => $error };
  $classifier->classify_error($error, $impact_event);
  
  my $impact = $impact_event->{tags}{business_impact} || 'unknown';
  printf "  %-40s -> %s impact\n",
         substr($error, 0, 35) . (length($error) > 35 ? "..." : ""),
         uc($impact);
}
print "\n";

print "5. 🚀 INTEGRATED ADVANCED PROCESSING DEMO\n";
print "-" x 40, "\n";

# Demo 5a: Full pipeline processing
print "Demo 5a: Complete error processing pipeline\n";

# Configure the advanced handler with custom rules
$advanced_handler->configure_fingerprinting({
  custom_rules => [
    sub {
      my ($exception, $event_data) = @_;
      if ($event_data->{contexts}{request}{url} =~ /\/api\/v(\d+)\//) {
        return sha256_hex("api_v$1:" . ($event_data->{tags}{error_category} || 'unknown'));
      }
      return undef;
    }
  ]
});

$advanced_handler->configure_context_enrichment({
  processors => [
    sub {
      my ($event_data, $exception, $options) = @_;
      $event_data->{contexts}{demo} = {
        processing_stage => 'phase3_demo',
        timestamp => time(),
        demo_version => '1.0',
      };
    }
  ]
});

# Process several different types of errors
my @demo_errors = (
  {
    exception => "Database connection failed",
    event_data => {
      message => "Database connection failed",
      level => 'error',
      contexts => { request => { url => '/api/v2/users', method => 'POST' } }
    },
    options => { user_id => 'user_123', priority => 'high' }
  },
  {
    exception => "Invalid user input",
    event_data => {
      message => "Invalid email format provided",
      level => 'warning',
      contexts => { request => { url => '/register', method => 'POST' } }
    },
    options => { user_id => 'user_456', customer_tier => 'standard' }
  },
  {
    exception => "Payment processing timeout",
    event_data => {
      message => "Credit card processing timeout after 30s",
      level => 'error',
      contexts => { 
        request => { url => '/checkout/process', method => 'POST' },
        transaction => { type => 'payment', payment_method => 'credit_card' }
      }
    },
    options => { user_id => 'user_789', customer_tier => 'vip', priority => 'critical' }
  }
);

for my $i (0..$#demo_errors) {
  my $demo = $demo_errors[$i];
  print "  Processing error " . ($i + 1) . ": " . substr($demo->{event_data}{message}, 0, 30) . "...\n";
  
  my $processed_event = $advanced_handler->process_error(
    $demo->{exception}, 
    $demo->{event_data}, 
    $demo->{options}
  );
  
  if ($processed_event) {
    printf "    ✓ PROCESSED - Level: %s, Category: %s, Fingerprint: %s\n",
           $processed_event->{level},
           $processed_event->{tags}{error_category} || 'none',
           $processed_event->{fingerprint} ? 'custom' : 'default';
    
    if ($processed_event->{extra}{sampling}) {
      printf "    📊 Sampling: %.0f%% rate, reason: %s\n",
             $processed_event->{extra}{sampling}{sample_rate} * 100,
             $processed_event->{extra}{sampling}{reason};
    }
  } else {
    print "    ✗ DROPPED (not sampled)\n";
  }
  print "\n";
}

# Demo 5b: Performance metrics
print "Demo 5b: Processing performance metrics\n";
my $metrics = $advanced_handler->get_processing_metrics();

printf "  Errors processed: %d\n", $metrics->{errors_processed};
printf "  Errors sampled: %d\n", $metrics->{errors_sampled};  
printf "  Errors dropped: %d\n", $metrics->{errors_dropped};
printf "  Average processing time: %.2f ms\n", ($metrics->{average_processing_time} || 0) * 1000;
printf "  Sampling rate: %.1f%%\n", ($metrics->{sampling_rate} || 0) * 100;

if ($metrics->{errors_processed} > 0) {
  print "\n  Component performance breakdown:\n";
  printf "    Fingerprinting: %.2f ms avg\n", ($metrics->{fingerprinting_time} / $metrics->{errors_processed}) * 1000;
  printf "    Context enrichment: %.2f ms avg\n", ($metrics->{context_enrichment_time} / $metrics->{errors_processed}) * 1000;
  printf "    Sampling: %.2f ms avg\n", ($metrics->{sampling_time} / $metrics->{errors_processed}) * 1000;
  printf "    Classification: %.2f ms avg\n", ($metrics->{classification_time} / $metrics->{errors_processed}) * 1000;
}
print "\n";

print "6. 🛠️  CONFIGURATION DEMO\n";
print "-" x 25, "\n";

# Demo 6a: Production vs Development configurations  
print "Demo 6a: Environment-specific configurations\n";

my $prod_handler = Sentry::ErrorHandling::Advanced->new();
$prod_handler->configure_for_production();

my $dev_handler = Sentry::ErrorHandling::Advanced->new();
$dev_handler->configure_for_development();

print "  Production config:\n";
printf "    Base sample rate: %.0f%%\n", $prod_handler->sampler->config->{base_sample_rate} * 100;
printf "    Max errors/min: %d\n", $prod_handler->sampler->config->{max_errors_per_minute};
printf "    PII scrubbing: %s\n", $prod_handler->context_enricher->config->{scrub_pii} ? 'enabled' : 'disabled';

print "  Development config:\n";
printf "    Base sample rate: %.0f%%\n", $dev_handler->sampler->config->{base_sample_rate} * 100;
printf "    Max errors/min: %d\n", $dev_handler->sampler->config->{max_errors_per_minute};
printf "    PII scrubbing: %s\n", $dev_handler->context_enricher->config->{scrub_pii} ? 'enabled' : 'disabled';
print "\n";

print "=" x 50, "\n";
print "🎉 Phase 3 Advanced Error Handling Demo Complete!\n\n";

print "✨ Features demonstrated:\n";
print "  • Smart error fingerprinting with custom rules\n";
print "  • Rich context enrichment with automatic and custom data\n";
print "  • Intelligent sampling (priority, frequency, custom rules)\n";
print "  • Advanced error classification (severity, category, impact)\n";
print "  • Integrated processing pipeline with metrics\n";
print "  • Environment-specific configurations\n\n";

print "🚀 Ready for Phase 2: Custom Instrumentation!\n";