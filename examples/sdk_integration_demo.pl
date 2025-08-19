#!/usr/bin/env perl
use strict;
use warnings;
use lib './lib';

use Sentry::SDK;
use Data::Dumper;
use Time::HiRes qw(sleep);

=head1 NAME

sdk_integration_demo.pl - Demo of Phase 3 Advanced Error Handling integrated with Sentry SDK

=head1 DESCRIPTION

Shows how to use the advanced error handling features through the main Sentry SDK interface.

=cut

print "🚀 Phase 3: Advanced Error Handling + SDK Integration Demo\n";
print "=" x 60, "\n\n";

# Mock DSN for testing (won't actually send)
my $mock_dsn = 'https://abc123@o12345.ingest.sentry.io/67890';

print "1. 🔧 SDK INITIALIZATION WITH ADVANCED ERROR HANDLING\n";
print "-" x 50, "\n";

# Initialize SDK with advanced error handling enabled
Sentry::SDK->init({
  dsn => $mock_dsn,
  environment => 'development',
  
  # Enable advanced error handling
  advanced_error_handling => 1,
  
  # Configure advanced error handling
  advanced_error_handling_config => {
    # Fingerprinting configuration
    fingerprinting => {
      custom_rules => [
        sub {
          my ($exception, $event_data) = @_;
          
          # Custom fingerprinting for database errors
          if ($event_data->{tags} && $event_data->{tags}{error_category} eq 'database') {
            require Digest::SHA;
            my $operation = $event_data->{contexts}{database}{operation} || 'unknown';
            return Digest::SHA::sha256_hex("db_error:$operation");
          }
          
          return undef;
        }
      ]
    },
    
    # Context enrichment configuration
    context_enrichment => {
      processors => [
        sub {
          my ($event_data, $exception, $options) = @_;
          
          # Add custom application context
          $event_data->{contexts}{demo_app} = {
            version => '2.0.0',
            module => 'integration_demo',
            feature => 'advanced_error_handling',
            timestamp => time(),
          };
        }
      ]
    },
    
    # Sampling configuration
    sampling => {
      sampling_config => {
        base_sample_rate => 0.8,  # 80% sampling for demo
        max_errors_per_minute => 20,
      },
      custom_rules => [
        sub {
          my ($exception, $event_data, $options, $current_result) = @_;
          
          # Always sample demo errors
          if ($event_data->{contexts} && $event_data->{contexts}{demo_app}) {
            return { sample_rate => 1.0, reason => 'demo_error' };
          }
          
          return undef;
        }
      ]
    },
    
    # Classification configuration  
    classification => {
      severity_patterns => {
        critical => [
          qr/demo.*critical/i,
        ]
      },
      category_patterns => {
        demo => [
          qr/demo|example|test/i,
        ]
      }
    }
  },
  
  # Disable default integrations for cleaner demo
  disabled_integrations => ['DBI', 'LwpUserAgent', 'MojoUserAgent', 'MojoTemplate'],
});

print "✓ SDK initialized with advanced error handling\n\n";

print "2. 📊 ERROR CAPTURE WITH CONTEXT\n";
print "-" x 35, "\n";

# Set some scope context
Sentry::SDK->configure_scope(sub {
  my $scope = shift;
  
  $scope->set_user({
    id => 'user_12345',
    username => 'demo_user',
    email => 'demo@example.com',
  });
  
  $scope->set_context('request', {
    method => 'POST',
    url => '/api/demo/error',
    user_agent => 'DemoClient/1.0',
  });
  
  $scope->set_tag('demo_session', 'advanced_error_handling');
  $scope->set_tag('test_scenario', 'sdk_integration');
});

print "✓ Scope configured with user and request context\n\n";

print "3. 🎭 ERROR SCENARIOS\n";
print "-" x 20, "\n";

# Scenario 1: Simple error with automatic processing
print "Scenario 1: Simple application error\n";
eval {
  die "Demo application error for testing";
};

my $event_id_1 = Sentry::SDK->capture_exception($@, {
  level => 'error',
  priority => 'medium',
});

print "  ✓ Captured with event ID: " . ($event_id_1 || 'not sampled') . "\n\n";

# Scenario 2: Database-like error
print "Scenario 2: Database connection error\n";
eval {
  # Simulate database error
  require Mojo::Exception;
  my $db_error = Mojo::Exception->new("Database connection timeout after 30 seconds")->trace;
  die $db_error;
};

my $event_id_2 = Sentry::SDK->capture_exception($@, {
  level => 'error',
  priority => 'high',
  database_operation => 'connect',
});

print "  ✓ Captured with event ID: " . ($event_id_2 || 'not sampled') . "\n\n";

# Scenario 3: Critical system error
print "Scenario 3: Critical system error\n";
eval {
  die "Demo critical system failure - immediate attention required";
};

my $event_id_3 = Sentry::SDK->capture_exception($@, {
  level => 'fatal',
  priority => 'critical',
  customer_tier => 'enterprise',
});

print "  ✓ Captured with event ID: " . ($event_id_3 || 'not sampled') . "\n\n";

# Scenario 4: Frequent error (should be sampled less)
print "Scenario 4: Frequent error simulation\n";
my $sampled_count = 0;
my $total_count = 10;

for my $i (1..$total_count) {
  eval {
    die "Frequent demo error #$i - cache miss";
  };
  
  my $event_id = Sentry::SDK->capture_exception($@, {
    level => 'warning',
    priority => 'low',
  });
  
  $sampled_count++ if $event_id;
  
  sleep 0.1;  # Brief delay
}

printf "  ✓ %d/%d frequent errors sampled (%.0f%%)\n\n", 
       $sampled_count, $total_count, ($sampled_count/$total_count) * 100;

# Scenario 5: Error with rich context
print "Scenario 5: Error with rich context\n";
Sentry::SDK->configure_scope(sub {
  my $scope = shift;
  
  # Add transaction-specific context
  $scope->set_context('transaction', {
    type => 'payment',
    payment_method => 'credit_card',
    amount => 99.99,
    currency => 'USD',
  });
  
  $scope->set_context('session', {
    id => 'sess_demo_12345',
    started_at => time() - 300,  # 5 minutes ago
    page_views => 15,
  });
  
  $scope->set_extra('debug_info', {
    memory_usage => '45MB',
    cache_hits => 234,
    cache_misses => 12,
  });
});

eval {
  die "Payment processing failed - card declined";
};

my $event_id_5 = Sentry::SDK->capture_exception($@, {
  level => 'error',
  priority => 'high',
  customer_tier => 'premium',
  session_id => 'sess_demo_12345',
  user_id => 'user_12345',
});

print "  ✓ Captured with rich context, event ID: " . ($event_id_5 || 'not sampled') . "\n\n";

print "4. 📈 ADVANCED PROCESSING METRICS\n";
print "-" x 35, "\n";

# Access the client to get advanced handler metrics
my $hub = Sentry::Hub->get_current_hub();
my $client = $hub->get_client();

if ($client && $client->advanced_error_handler) {
  my $metrics = $client->advanced_error_handler->get_processing_metrics();
  
  print "Processing Performance:\n";
  printf "  • Total errors processed: %d\n", $metrics->{errors_processed};
  printf "  • Errors sampled: %d\n", $metrics->{errors_sampled};
  printf "  • Errors dropped: %d\n", $metrics->{errors_dropped};
  printf "  • Average processing time: %.2f ms\n", ($metrics->{average_processing_time} || 0) * 1000;
  printf "  • Sampling rate: %.1f%%\n", ($metrics->{sampling_rate} || 0) * 100;
  
  if ($metrics->{errors_processed} > 0) {
    print "\nComponent Breakdown:\n";
    printf "  • Fingerprinting: %.2f ms avg\n", ($metrics->{fingerprinting_time} / $metrics->{errors_processed}) * 1000;
    printf "  • Context enrichment: %.2f ms avg\n", ($metrics->{context_enrichment_time} / $metrics->{errors_processed}) * 1000;
    printf "  • Sampling: %.2f ms avg\n", ($metrics->{sampling_time} / $metrics->{errors_processed}) * 1000;
    printf "  • Classification: %.2f ms avg\n", ($metrics->{classification_time} / $metrics->{errors_processed}) * 1000;
  }
} else {
  print "Advanced error handling not enabled or accessible.\n";
}

print "\n";

print "5. 🔍 INTEGRATION VERIFICATION\n";
print "-" x 30, "\n";

print "Checking SDK integration status:\n";
print "  ✓ SDK initialized: " . (defined $hub ? "YES" : "NO") . "\n";
print "  ✓ Client available: " . (defined $client ? "YES" : "NO") . "\n";
print "  ✓ Advanced handler: " . ($client && $client->advanced_error_handler ? "ENABLED" : "DISABLED") . "\n";
print "  ✓ Integrations active: " . (@{$client->integrations || []} . " integrations") . "\n";
print "  ✓ Environment: " . ($client->_options->{environment} || 'not set') . "\n\n";

print "=" x 60, "\n";
print "🎉 SDK Integration Demo Complete!\n\n";

print "✨ Features demonstrated:\n";
print "  • Advanced error handling through SDK interface\n";
print "  • Custom configuration of all error handling components\n";
print "  • Context-aware error processing\n";  
print "  • Intelligent sampling with custom rules\n";
print "  • Automatic classification and fingerprinting\n";
print "  • Performance metrics and monitoring\n";
print "  • Seamless integration with existing SDK features\n\n";

print "🚀 Advanced Error Handling is now fully integrated!\n";
print "   Ready to proceed to Phase 2: Custom Instrumentation\n";