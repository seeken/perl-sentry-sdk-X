#!/usr/bin/env perl
use strict;
use warnings;
use lib 'lib';

use Sentry::SDK;
use Sentry::Instrumentation::Metrics;
use Sentry::Instrumentation::Spans;
use Sentry::Instrumentation::Aggregator;
use Sentry::Hub;
use Time::HiRes qw(time sleep);

# Initialize Sentry with real DSN for testing
my $sentry_dsn = $ENV{SENTRY_TEST_DSN};
if ($sentry_dsn) {
  print "🔗 Initializing Sentry SDK with real backend...\n";
  Sentry::SDK->init({
    dsn => $sentry_dsn,
    environment => 'custom_instrumentation_demo',
    release => 'perl-sdk-phase2-custom-instrumentation',
    traces_sample_rate => 1.0,
  });
  
  # Set demo context
  Sentry::SDK->configure_scope(sub {
    my ($scope) = @_;
    $scope->set_tag("demo", "custom_instrumentation");
    $scope->set_tag("phase", "phase2");
    $scope->set_user({
      id => "demo_user",
      username => "perl_developer", 
    });
  });
  print "✅ Connected to real Sentry backend\n\n";
} else {
  print "ℹ️  No SENTRY_TEST_DSN found - demo will run without real backend\n\n";
}
use Data::Dumper;

=head1 NAME

custom_instrumentation_demo.pl - Phase 2: Custom Instrumentation Demo

=head1 DESCRIPTION

Comprehensive demonstration of Phase 2 Custom Instrumentation features:
- Custom metrics collection (counters, gauges, histograms, distributions, sets)
- Custom span creation and management
- Batch operations and error handling
- Metrics aggregation and reporting
- Performance monitoring and measurement

=cut

print "🎯 Phase 2: Custom Instrumentation Demo\n";
print "=" x 45, "\n\n";

print "🚀 Features demonstrated:\n";
print "  • Custom metrics (counters, gauges, histograms, sets)\n";
print "  • Custom spans with automatic context propagation\n";
print "  • Batch operations with item-level tracking\n";
print "  • Performance timing and measurement\n";
print "  • Metrics aggregation and reporting\n";
print "  • Error handling within instrumented code\n\n";

# Initialize instrumentation components
my $metrics = Sentry::Instrumentation::Metrics->new(
  name_prefix => 'demo.',
  default_tags => { 
    service => 'custom_instrumentation_demo',
    version => '2.0',
    environment => 'development'
  },
  enabled => 1
);

my $spans = Sentry::Instrumentation::Spans->new(
  enabled => 1,
  default_tags => {
    component => 'demo',
    instrumentation => 'custom'
  },
  auto_finish => 1
);

my $aggregator = Sentry::Instrumentation::Aggregator->new(
  flush_interval => 30,
  batch_size => 20,
  auto_flush => 0  # Manual control for demo
);

print "1. 📊 CUSTOM METRICS DEMONSTRATION\n";
print "-" x 35, "\n";

# Demo 1a: Counter metrics
print "Demo 1a: Counter metrics\n";
print "  📈 Incrementing request counters...\n";

for my $i (1..5) {
  $metrics->increment('api.requests', 1, { 
    endpoint => '/api/users',
    method => 'GET',
    status => ($i % 4 == 0) ? '500' : '200'
  });
  
  $metrics->increment('api.requests', 1, {
    endpoint => '/api/orders', 
    method => 'POST',
    status => '201'
  });
}

# Fluent API
$metrics->counter('background.jobs')
        ->increment(3)
        ->increment(2);

print "  ✓ Recorded API request metrics with different endpoints and status codes\n";
print "  ✓ Used fluent API for background job counters\n\n";

# Demo 1b: Gauge metrics
print "Demo 1b: Gauge metrics\n";
print "  📊 Recording system resource gauges...\n";

$metrics->gauge('system.memory_usage', 1024 * 1024 * 512, { type => 'heap' });
$metrics->gauge('system.cpu_usage', 75.5, { core => 'all' });
$metrics->gauge('database.connections', 25, { pool => 'primary' });

# Fluent API for gauge
$metrics->gauge('queue.size')->set(150, { queue => 'emails' });
$metrics->gauge('cache.hit_rate')->set(0.87, { cache => 'redis' });

print "  ✓ Recorded memory, CPU, and database connection gauges\n";
print "  ✓ Set queue size and cache hit rate using fluent API\n\n";

# Demo 1c: Histogram metrics (timing distributions)
print "Demo 1c: Histogram and timing metrics\n";
print "  📏 Recording response time distributions...\n";

my @response_times = (0.015, 0.023, 0.156, 0.089, 0.234, 0.067, 0.445, 0.012, 0.078, 0.234);
for my $time (@response_times) {
  $metrics->histogram('http.response_time')->record($time, { endpoint => '/api/users' });
}

# Timing convenience method
$metrics->timing('db.query_time', 0.025, { operation => 'select', table => 'users' });
$metrics->timing('db.query_time', 0.156, { operation => 'insert', table => 'orders' });
$metrics->timing('db.query_time', 0.089, { operation => 'update', table => 'users' });

print "  ✓ Recorded HTTP response time histogram with " . scalar(@response_times) . " samples\n";
print "  ✓ Used timing convenience method for database query times\n\n";

# Demo 1d: Set metrics (unique value tracking)
print "Demo 1d: Set metrics for unique value tracking\n";
print "  🎯 Tracking unique users and sessions...\n";

my @users = ('user123', 'user456', 'user789', 'user123', 'user101', 'user456');
for my $user (@users) {
  $metrics->set('active_users')->add($user, { session_type => 'web' });
}

my @sessions = ('sess_abc', 'sess_def', 'sess_ghi', 'sess_abc');
for my $session (@sessions) {
  $metrics->set('active_sessions')->add($session);
}

print "  ✓ Tracked " . scalar(@users) . " user interactions (with deduplication)\n";
print "  ✓ Tracked " . scalar(@sessions) . " session interactions\n\n";

print "2. 🔍 CUSTOM SPANS DEMONSTRATION\n";
print "-" x 32, "\n";

# Demo 2a: Basic span creation
print "Demo 2a: Basic custom spans\n";
print "  📋 Creating spans for business operations...\n";

my $transaction = $spans->start_transaction('demo.workflow', 'Custom instrumentation demo workflow');

my $auth_span = $spans->start_span('auth.verify', 'Verify user credentials', {
  tags => { user_id => 'demo_user', auth_method => 'jwt' },
  data => { token_age => 3600, scopes => ['read', 'write'] }
});

sleep(0.05);  # Simulate work
$auth_span->set_status('ok')->finish();

my $db_span = $spans->start_span('db.user_lookup', 'Fetch user profile', {
  tags => { database => 'primary', table => 'users' },
  data => { user_id => 'demo_user', cache_hit => 0 }
});

sleep(0.03);  # Simulate database query
$db_span->set_data('rows_returned', 1)->set_status('ok')->finish();

print "  ✓ Created authentication span with JWT verification\n";
print "  ✓ Created database lookup span with query details\n\n";

# Demo 2b: Nested spans with trace method
print "Demo 2b: Nested spans and trace method\n";
print "  🔄 Using trace method for automatic span management...\n";

my $result = $spans->trace('business.process_order', sub {
  # Simulate order processing with nested operations
  
  my $validation_result = $spans->trace('validation.order', sub {
    sleep(0.02);
    return { valid => 1, total => 99.99 };
  }, {
    op => 'validation.business',
    tags => { validator => 'order_validator_v2' }
  });
  
  my $payment_result = $spans->trace('payment.charge', sub {
    sleep(0.04);  # Simulate payment processing
    return { success => 1, transaction_id => 'txn_12345' };
  }, {
    op => 'payment.external',
    tags => { payment_method => 'stripe', amount => $validation_result->{total} }
  });
  
  return {
    order_id => 'order_67890',
    status => 'completed',
    payment => $payment_result
  };
}, {
  op => 'business.order_processing',
  description => 'Complete order processing workflow',
  tags => { order_type => 'standard', priority => 'normal' }
});

print "  ✓ Processed order with nested validation and payment spans\n";
print "  ✓ Used trace method for automatic span lifecycle management\n";
print "  ✓ Order result: " . $result->{order_id} . " - " . $result->{status} . "\n\n";

# Demo 2c: Batch operations
print "Demo 2c: Batch operations with item tracking\n";
print "  📦 Processing batch of notifications...\n";

my @notifications = (
  { id => 'notif_1', type => 'email', user => 'user123' },
  { id => 'notif_2', type => 'sms', user => 'user456' },
  { id => 'notif_3', type => 'push', user => 'user789' },
  { id => 'notif_4', type => 'email', user => 'user101' },
  { id => 'notif_5', type => 'webhook', user => 'user202' }
);

my $batch = $spans->start_batch(
  'notifications.send_batch',
  \@notifications,
  {
    tags => { batch_type => 'user_notifications', priority => 'standard' },
    data => { batch_id => 'batch_001' }
  }
);

for my $notif (@notifications) {
  $batch->process_item($notif->{id}, sub {
    # Simulate notification sending
    sleep(0.01 + rand(0.02));
    
    # Simulate occasional failure
    if ($notif->{id} eq 'notif_4') {
      die "Webhook endpoint unreachable";
    }
    
    return { sent => 1, delivery_time => time() };
  }, {
    tags => { notification_type => $notif->{type}, user_id => $notif->{user} }
  });
}

$batch->finish();
print "  ✓ Processed batch of " . scalar(@notifications) . " notifications\n";
print "  ✓ Tracked individual item success/failure rates\n";
print "  ✓ Handled batch-level error reporting\n\n";

$transaction->finish();

print "3. ⏱️  PERFORMANCE MEASUREMENT\n";
print "-" x 30, "\n";

# Demo 3a: Time measurement
print "Demo 3a: Performance timing with metrics\n";
print "  ⏲️  Measuring expensive operations...\n";

my $computation_result = $metrics->time_block('expensive.computation', sub {
  # Simulate CPU-intensive work
  my $sum = 0;
  for my $i (1..100000) {
    $sum += sqrt($i);
  }
  return $sum;
}, { algorithm => 'sqrt_sum', iterations => 100000 });

my $io_result = $spans->measure_timing('io.file_processing', sub {
  # Simulate I/O operations
  sleep(0.1);
  return { files_processed => 5, total_size => 1024 * 50 };
}, {
  tags => { operation_type => 'bulk_read', file_count => 5 }
});

print "  ✓ Timed expensive computation: " . sprintf("%.2f", $computation_result) . "\n";
print "  ✓ Timed I/O operations: " . $io_result->{files_processed} . " files\n\n";

# Demo 3b: Mixed metrics and spans
print "Demo 3b: Combined metrics and spans\n";
print "  🎭 Coordinating metrics collection with span tracing...\n";

my $api_span = $spans->start_span('api.complex_endpoint', 'Complex API endpoint with metrics');

# Collect metrics within span context
$metrics->increment('api.endpoint.calls', 1, { endpoint => 'complex', version => 'v2' });

my $cache_lookup_result = $spans->trace('cache.lookup', sub {
  sleep(0.01);
  my $hit = rand() > 0.3;  # 70% hit rate
  
  $metrics->increment('cache.requests', 1, { result => $hit ? 'hit' : 'miss' });
  $metrics->gauge('cache.hit_rate', $hit ? 0.7 : 0.3);
  
  return { hit => $hit, data => $hit ? { cached_data => 'value' } : undef };
}, { tags => { cache_type => 'redis', ttl => 3600 } });

if (!$cache_lookup_result->{hit}) {
  # Cache miss - fetch from database
  $spans->trace('db.fetch_data', sub {
    sleep(0.05);  # Simulate database query
    $metrics->increment('db.queries', 1, { table => 'complex_data', cache_miss => 1 });
    $metrics->timing('db.query_duration', 0.05, { operation => 'select' });
    return { data => 'fetched_from_db' };
  });
}

$api_span->set_data('cache_hit', $cache_lookup_result->{hit} ? 1 : 0)
         ->set_status('ok')
         ->finish();

print "  ✓ Combined span tracing with metrics collection\n";
print "  ✓ Cache " . ($cache_lookup_result->{hit} ? "HIT" : "MISS") . " - metrics updated accordingly\n\n";

print "4. 📈 METRICS AGGREGATION AND REPORTING\n";
print "-" x 40, "\n";

# Demo 4a: Collect all metrics for aggregation
print "Demo 4a: Metrics collection and aggregation\n";
print "  📊 Aggregating collected metrics...\n";

$aggregator->collect_metrics($metrics);

my $pre_flush_stats = $aggregator->get_stats();
print "  📋 Pre-flush statistics:\n";
print "    • Metrics collected: " . $pre_flush_stats->{metrics_collected} . "\n";
print "    • Buffer size: " . $pre_flush_stats->{buffer_size} . "\n";
print "    • Time since last flush: " . sprintf("%.2fs", $pre_flush_stats->{time_since_last_flush}) . "\n\n";

# Demo 4b: Manual flush and statistics
print "Demo 4b: Metrics flush and final statistics\n";
print "  🚀 Flushing aggregated metrics...\n";

$aggregator->flush();

my $post_flush_stats = $aggregator->get_stats();
print "  📋 Post-flush statistics:\n";
print "    • Metrics flushed: " . $post_flush_stats->{metrics_flushed} . "\n";
print "    • Batches sent: " . $post_flush_stats->{batches_sent} . "\n";
print "    • Flush duration: " . sprintf("%.3fs", $post_flush_stats->{last_flush_duration}) . "\n";
print "    • Flush efficiency: " . sprintf("%.1f%%", ($post_flush_stats->{flush_efficiency} || 0) * 100) . "\n\n";

print "5. 📊 METRICS SUMMARY\n";
print "-" x 20, "\n";

# Demo 5: Show collected metrics summary
print "Demo 5: Collected metrics summary\n";
print "  📋 Overview of all collected metrics...\n";

my $all_metrics = $metrics->get_metrics();

print "  📈 Counters:\n";
for my $key (keys %{$all_metrics->{counters} || {}}) {
  my $counter = $all_metrics->{counters}{$key};
  print "    • " . $counter->{name} . ": " . $counter->{value} . "\n";
}

print "  📊 Gauges:\n";
for my $key (keys %{$all_metrics->{gauges} || {}}) {
  my $gauge = $all_metrics->{gauges}{$key};
  my $value = ref($gauge->{value}) ? 'complex' : $gauge->{value};
  print "    • " . $gauge->{name} . ": " . $value . "\n";
}

print "  📏 Histograms:\n";
for my $key (keys %{$all_metrics->{histograms} || {}}) {
  my $hist = $all_metrics->{histograms}{$key};
  my $stats = $hist->{statistics};
  printf "    • %s: %d samples, avg=%.3fs, p95=%.3fs\n", 
         $hist->{name}, $stats->{count}, $stats->{mean}, $stats->{p95};
}

print "  🎯 Sets:\n";
for my $key (keys %{$all_metrics->{sets} || {}}) {
  my $set = $all_metrics->{sets}{$key};
  print "    • " . $set->{name} . ": " . $set->{unique_count} . " unique values\n";
}

print "\n";

print "6. 🧹 CLEANUP AND FINALIZATION\n";
print "-" x 32, "\n";

# Demo 6: Cleanup
print "Demo 6: Cleanup and finalization\n";
print "  🧽 Finishing remaining spans and final flush...\n";

$spans->finish_all_spans();
$aggregator->flush();
$aggregator->stop();

print "  ✓ All spans finished\n";
print "  ✓ Final metrics flush completed\n";
print "  ✓ Aggregator stopped\n\n";

print "=" x 45, "\n";
print "🎉 Phase 2: Custom Instrumentation Demo Complete!\n\n";

print "✨ Successfully demonstrated:\n";
print "  • ✅ Custom metrics collection (counters, gauges, histograms, sets)\n";
print "  • ✅ Fluent API for metrics with tags and metadata\n";
print "  • ✅ Custom span creation with automatic lifecycle management\n";
print "  • ✅ Nested spans and trace methods for code blocks\n";
print "  • ✅ Batch operations with individual item tracking\n";
print "  • ✅ Performance timing and measurement utilities\n";
print "  • ✅ Coordinated metrics and spans for complex operations\n";
print "  • ✅ Efficient metrics aggregation and batching\n";
print "  • ✅ Statistical analysis of metric distributions\n";
print "  • ✅ Comprehensive error handling and cleanup\n\n";

print "🚀 Ready for SDK integration (Phase 2 complete)!\n";
print "Next: Phase 1 - Performance Optimization\n";