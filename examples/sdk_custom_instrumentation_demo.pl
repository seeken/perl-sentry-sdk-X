#!/usr/bin/env perl
use strict;
use warnings;
use lib 'lib';

use Sentry::SDK;
use Time::HiRes qw(sleep);

print "🎯 SDK Custom Instrumentation Integration Demo\n";
print "=" x 50 . "\n\n";

# Initialize Sentry with real DSN for testing
my $sentry_dsn = $ENV{SENTRY_TEST_DSN};
if ($sentry_dsn) {
  print "🔗 Initializing Sentry SDK with real backend...\n";
  Sentry::SDK->init({
    dsn => $sentry_dsn,
    environment => 'sdk_integration_demo',
    release => 'perl-sdk-custom-instrumentation-integration',
    traces_sample_rate => 1.0,
  });
  
  # Set demo context
  Sentry::SDK->configure_scope(sub {
    my ($scope) = @_;
    $scope->set_tag("demo", "sdk_custom_instrumentation");
    $scope->set_tag("integration", "main_sdk");
    $scope->set_user({
      id => "sdk_demo_user",
      username => "perl_sdk_developer", 
    });
  });
  print "✅ Connected to real Sentry backend\n\n";
} else {
  print "ℹ️  No SENTRY_TEST_DSN found - demo will run without real backend\n\n";
}

print "🚀 Demonstrating SDK integrated custom instrumentation:\n";
print "  • Direct SDK API calls for metrics and spans\n";
print "  • Seamless integration with existing SDK features\n";
print "  • Combined error tracking and custom telemetry\n";
print "  • Automatic aggregation and transport\n\n";

# Start the aggregator for automatic batching
Sentry::SDK->start_aggregator();

print "1. 📊 METRICS THROUGH SDK API\n";
print "-----------------------------\n";

print "Demo 1a: Counter metrics via SDK\n";
Sentry::SDK->increment('sdk.api.calls', 1, { method => 'increment' });
Sentry::SDK->increment('sdk.demo.requests', 5, { endpoint => '/metrics' });
print "  ✓ Incremented counters via Sentry::SDK->increment()\n";

print "Demo 1b: Gauge metrics via SDK\n";
Sentry::SDK->gauge('sdk.memory.usage', 128 * 1024 * 1024, { unit => 'bytes' });
Sentry::SDK->gauge('sdk.active.connections', 42, { pool => 'database' });
print "  ✓ Set gauges via Sentry::SDK->gauge()\n";

print "Demo 1c: Histogram metrics via SDK\n";
Sentry::SDK->histogram('sdk.response.time', 150.5, { endpoint => '/users' });
Sentry::SDK->histogram('sdk.processing.duration', 89.2, { task => 'data_processing' });
print "  ✓ Recorded histograms via Sentry::SDK->histogram()\n";

print "Demo 1d: Set and timing metrics via SDK\n";
Sentry::SDK->set('sdk.unique.users', 'user_' . int(rand(1000)), { session => 'web' });
Sentry::SDK->timing('sdk.cache.lookup', 12.3, { cache => 'redis' });
print "  ✓ Tracked sets and timing via Sentry::SDK methods\n\n";

print "2. 🔍 CUSTOM SPANS THROUGH SDK API\n";
print "----------------------------------\n";

print "Demo 2a: Basic custom spans\n";
my $auth_span = Sentry::SDK->start_span('sdk.authentication', 'User authentication flow');
$auth_span->set_data('method', 'oauth2');
$auth_span->set_data('provider', 'google');
sleep(0.05);  # Simulate work
$auth_span->finish();
print "  ✓ Created custom span via Sentry::SDK->start_span()\n";

print "Demo 2b: Trace method with automatic span management\n";
my $order_result = Sentry::SDK->trace('sdk.order.processing', sub {
  # Simulate complex order processing
  Sentry::SDK->increment('sdk.orders.processed', 1, { status => 'success' });
  sleep(0.03);
  return { order_id => 'order_' . int(rand(10000)), status => 'completed' };
}, 'Processing customer order via SDK');

print "  ✓ Used trace method for automatic span management\n";
print "  ✓ Order result: $order_result->{order_id} - $order_result->{status}\n";

print "Demo 2c: Batch processing spans\n";
my $batch = Sentry::SDK->start_batch('sdk.data.migration', 'Migrating user data');
for my $i (1..3) {
  my $user_id = "user_$i";
  $batch->process_item($user_id, sub {
    # Simulate data migration
    Sentry::SDK->increment('sdk.migrations.completed', 1, { table => 'users' });
    sleep(0.01);
    if ($i == 2) {
      die "Migration failed for user $user_id";  # Simulate error
    }
  });
}
$batch->finish();
print "  ✓ Processed batch with item-level tracking via SDK\n\n";

print "3. ⏱️  PERFORMANCE MEASUREMENT VIA SDK\n";
print "-------------------------------------\n";

print "Demo 3a: Time block measurement\n";
my $computation_result = Sentry::SDK->time_block('sdk.heavy.computation', sub {
  # Simulate expensive computation
  my $result = 0;
  for my $i (1..50000) {
    $result += sqrt($i);
  }
  return $result;
}, { algorithm => 'sqrt_sum', iterations => 50000 });

print "  ✓ Timed computation block: $computation_result\n";

print "Demo 3b: Measure timing with return values\n";
my ($file_count, $duration) = Sentry::SDK->measure_timing('sdk.file.processing', sub {
  # Simulate file processing
  sleep(0.02);
  return scalar(glob("lib/Sentry/*.pm"));
}, { operation => 'file_scan' });

print "  ✓ Processed $file_count files in ${duration}ms\n\n";

print "4. 🎭 COMBINED SDK FEATURES\n";
print "---------------------------\n";

print "Demo 4a: Combining spans, metrics, and error tracking\n";
eval {
  Sentry::SDK->trace('sdk.complex.workflow', sub {
    # Record metrics within span
    Sentry::SDK->increment('sdk.workflow.started', 1, { type => 'complex' });
    
    # Simulate work with nested measurement
    Sentry::SDK->time_block('sdk.workflow.validation', sub {
      sleep(0.01);
      Sentry::SDK->gauge('sdk.validation.rules', 25, { version => 'v2' });
    }, { step => 'validation' });
    
    # Simulate error for demonstration
    if (rand() > 0.5) {
      die "Workflow validation failed";
    }
    
    Sentry::SDK->increment('sdk.workflow.completed', 1, { status => 'success' });
  });
};

if ($@) {
  print "  ✓ Caught error in complex workflow (automatically sent to Sentry)\n";
  Sentry::SDK->increment('sdk.workflow.errors', 1, { type => 'validation' });
} else {
  print "  ✓ Complex workflow completed successfully\n";
}

print "Demo 4b: Transaction with custom instrumentation\n";
my $transaction = Sentry::SDK->start_transaction({
  name => 'sdk_custom_instrumentation_demo',
  op => 'demo.execution',
});

Sentry::SDK->configure_scope(sub {
  my ($scope) = @_;
  $scope->set_span($transaction);
});

# Add custom instrumentation within transaction
Sentry::SDK->increment('sdk.transaction.metrics', 1, { transaction => 'demo' });
Sentry::SDK->histogram('sdk.transaction.duration', 250.5, { type => 'demo' });

$transaction->set_tag("custom_instrumentation", "enabled");
$transaction->finish();

print "  ✓ Completed transaction with integrated custom metrics\n\n";

print "5. 📈 METRICS AGGREGATION AND REPORTING\n";
print "---------------------------------------\n";

print "Demo 5a: Check aggregation stats before flush\n";
my $pre_stats = Sentry::SDK->get_metrics_stats();
print "  📋 Pre-flush statistics:\n";
print "    • Metrics collected: $pre_stats->{metrics_collected}\n";
print "    • Buffer size: $pre_stats->{buffer_size}\n";
printf("    • Time since last flush: %.2fs\n", $pre_stats->{time_since_flush});

print "Demo 5b: Manual flush and final stats\n";
my $flush_stats = Sentry::SDK->flush_metrics();
print "  📋 Flush statistics:\n";
print "    • Metrics flushed: $flush_stats->{metrics_flushed}\n";
print "    • Batches sent: $flush_stats->{batches_sent}\n";
printf("    • Flush duration: %.3fs\n", $flush_stats->{flush_duration});
printf("    • Flush efficiency: %.1f%%\n", $flush_stats->{flush_efficiency});

print "\n6. 🧹 CLEANUP AND FINALIZATION\n";
print "-------------------------------\n";

print "Demo 6: Stop aggregator and final cleanup\n";
Sentry::SDK->stop_aggregator();
print "  ✓ Aggregator stopped with final flush\n";
print "  ✓ All resources cleaned up\n";

print "\n" . "=" x 50 . "\n";
print "🎉 SDK Custom Instrumentation Integration Complete!\n\n";

print "✨ Successfully demonstrated:\n";
print "  • ✅ Direct SDK API for all custom instrumentation features\n";
print "  • ✅ Seamless integration with existing SDK methods\n";
print "  • ✅ Combined error tracking and custom telemetry\n";
print "  • ✅ Automatic span and transaction integration\n";
print "  • ✅ Unified configuration and initialization\n";
print "  • ✅ Consistent fluent API across all features\n";
print "  • ✅ Automatic aggregation and transport\n";
print "  • ✅ Comprehensive documentation and examples\n";

if ($sentry_dsn) {
  print "\n🔍 Check your Sentry dashboard for:\n";
  print "   - Custom metrics sent as structured events\n";
  print "   - Custom spans within performance transactions\n";
  print "   - Error events with full context and custom tags\n";
  print "   - Combined telemetry data for comprehensive monitoring\n";
}

print "\n🚀 Phase 2 Custom Instrumentation: FULLY INTEGRATED!\n";
print "Next: Phase 1 - Performance Optimization\n";