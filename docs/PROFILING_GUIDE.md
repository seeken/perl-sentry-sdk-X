# Sentry Profiling Quick Start Guide

This guide helps you get started with continuous profiling in the Perl Sentry SDK. Profiling provides code-level performance insights by collecting stack traces at regular intervals.

## Prerequisites

- Sentry account with profiling enabled
- Perl Sentry SDK with profiling support
- Valid Sentry DSN

## Basic Setup

### 1. Enable Profiling

```perl
use Sentry::SDK;

Sentry::SDK->init({
    dsn => $ENV{SENTRY_DSN},
    
    # Enable tracing (required for profiling)
    traces_sample_rate => 1.0,      # 100% of transactions
    
    # Enable profiling
    enable_profiling => 1,
    profiles_sample_rate => 0.1,    # Profile 10% of transactions
    
    # Optional: Configure sampling interval
    sampling_interval_us => 10000,  # 10ms (good for production)
});
```

### 2. Automatic Profiling with Transactions

The easiest way to get profiling data is through transactions:

```perl
# Start a transaction - profiling begins automatically
my $transaction = Sentry::SDK->start_transaction({
    name => 'data-processing',
    op => 'task',
});

# Your application code
process_large_dataset();
run_complex_calculations();

# Finish transaction - profile is sent to Sentry
$transaction->finish();
```

### 3. Manual Profiling Control

For more control, use manual profiling:

```perl
# Start profiling
my $profile = Sentry::SDK->start_profiler({
    name => 'background-job'
});

# Your code to profile
expensive_computation();

# Stop profiling and send to Sentry
my $completed_profile = Sentry::SDK->stop_profiler();

# Optional: Get statistics
my $stats = $completed_profile->get_stats();
say "Collected " . $stats->{sample_count} . " samples";
```

### 4. Block-based Profiling

Profile a specific code block:

```perl
my $result = Sentry::SDK->profile(sub {
    my $data = load_data();
    my $processed = transform_data($data);
    return save_data($processed);
});
```

## Configuration Options

### Performance Tuning

```perl
Sentry::SDK->init({
    # Basic profiling
    enable_profiling => 1,
    profiles_sample_rate => 0.1,
    
    # Sampling configuration
    sampling_interval_us => 10000,  # 10ms - production ready
    # sampling_interval_us => 5000,   # 5ms - staging/testing
    # sampling_interval_us => 1000,   # 1ms - development only
    
    # Advanced features
    adaptive_sampling => 1,         # Adjust based on system load
    cpu_threshold_percent => 75,    # Reduce sampling if CPU > 75%
    memory_threshold_mb => 100,     # Reduce sampling if memory > 100MB
});
```

### Package Filtering

Skip profiling certain packages to reduce noise:

```perl
Sentry::SDK->init({
    enable_profiling => 1,
    profiles_sample_rate => 1.0,
    
    # Skip these packages in profiles
    ignore_packages => [
        'Test::', 'DBI', 'JSON::', 'LWP::'
    ],
});
```

### Production Configuration

Recommended settings for production:

```perl
Sentry::SDK->init({
    dsn => $ENV{SENTRY_DSN},
    
    # Conservative sampling rates
    traces_sample_rate => 0.1,      # 10% of transactions
    profiles_sample_rate => 0.05,   # 5% of transactions (50% of traces)
    
    # Enable profiling with adaptive sampling
    enable_profiling => 1,
    adaptive_sampling => 1,
    profile_lifecycle => 'trace',   # Only profile during transactions
    
    # Conservative sampling interval
    sampling_interval_us => 10000,  # 10ms
    
    # Resource limits
    cpu_threshold_percent => 80,
    memory_threshold_mb => 200,
    max_stack_depth => 30,
    
    # Filter noisy packages
    ignore_packages => ['Test::', 'DBI', 'DBD::'],
});
```

## Monitoring Profile Performance

### Check Profiling Status

```perl
my $profiler = Sentry::SDK->get_profiler();

if ($profiler) {
    if ($profiler->is_active()) {
        my $profile = $profiler->get_active_profile();
        my $stats = $profile->get_stats();
        
        say "Active profile:";
        say "  Samples: " . $stats->{sample_count};
        say "  Duration: " . $stats->{duration} . "s";
        say "  Unique frames: " . $stats->{unique_frames};
    } else {
        say "Profiler ready but inactive";
    }
} else {
    say "Profiling disabled";
}
```

### Measure Performance Impact

Use the provided benchmark script:

```bash
cd examples/
perl profiling_benchmark.pl
```

This will test different configurations and show performance overhead.

## Understanding Profile Data

### In Sentry Dashboard

1. Navigate to **Performance** > **Profiles**
2. Select a profile to view the flame graph
3. Look for:
   - **Hot paths**: Functions consuming the most time
   - **Call frequencies**: How often functions are called
   - **Stack depths**: Deep call chains that might be optimizable

### Interpreting Results

- **Wide bars**: Functions that consume significant total time
- **Tall stacks**: Deep recursion or call chains
- **Frequent samples**: Code paths executed often
- **Filtered frames**: System/library code (grayed out)

## Common Patterns

### Web Application Profiling

```perl
# In your web framework setup
Sentry::SDK->init({
    dsn => $ENV{SENTRY_DSN},
    traces_sample_rate => 0.2,
    profiles_sample_rate => 0.1,
    enable_profiling => 1,
    adaptive_sampling => 1,
    ignore_packages => ['Template::', 'DBI', 'JSON::'],
});

# In request handler
my $transaction = Sentry::SDK->start_transaction({
    name => $request->path,
    op => 'http.server',
});

# Request processing happens here - automatically profiled

$transaction->set_http_status($response->code);
$transaction->finish();
```

### Background Job Profiling

```perl
# For worker processes
Sentry::SDK->init({
    enable_profiling => 1,
    profiles_sample_rate => 1.0,    # Profile all jobs
    profile_lifecycle => 'manual',  # Manual control
    sampling_interval_us => 5000,   # Higher resolution
});

# Profile each job
my $profile = Sentry::SDK->start_profiler({
    name => "job-$job_id",
});

process_job($job_data);

Sentry::SDK->stop_profiler();
```

### Database Operation Profiling

```perl
# Profile expensive DB operations
my $result = Sentry::SDK->profile(sub {
    my $dbh = DBI->connect($dsn, $user, $pass);
    
    # Complex query profiling
    my $sth = $dbh->prepare($complex_query);
    $sth->execute(@params);
    
    return $sth->fetchall_arrayref();
});
```

## Troubleshooting

### High Overhead

If profiling causes performance issues:

1. **Reduce sampling rate**: Lower `profiles_sample_rate`
2. **Increase interval**: Higher `sampling_interval_us` 
3. **Enable adaptive sampling**: Set `adaptive_sampling => 1`
4. **Add resource limits**: Set `cpu_threshold_percent`

### Missing Profiles

If profiles aren't appearing in Sentry:

1. **Check sampling rates**: May be too low for testing
2. **Verify DSN**: Ensure correct project DSN
3. **Check transaction requirements**: Profiling needs tracing enabled
4. **Review filters**: `ignore_packages` might be too broad

### Limited Profile Data

For more detailed profiles:

1. **Decrease sampling interval**: Lower `sampling_interval_us`
2. **Increase stack depth**: Higher `max_stack_depth`
3. **Check package filters**: Remove `ignore_packages` temporarily
4. **Extend profile duration**: Longer-running operations provide more data

## Best Practices

1. **Start conservative**: Low sample rates in production
2. **Use adaptive sampling**: Automatically adjusts to system load
3. **Filter strategically**: Skip framework code, keep application code
4. **Monitor overhead**: Use benchmarking tools regularly
5. **Profile representative workloads**: Test with realistic data
6. **Correlate with metrics**: Compare profiles with performance metrics

## Next Steps

- Review example scripts: `examples/advanced_profiling_demo.pl`
- Run performance benchmarks: `examples/profiling_benchmark.pl`
- Check the full SDK documentation in `README.md`
- Visit [Sentry's profiling documentation](https://docs.sentry.io/product/profiling/) for platform-agnostic guides

For questions or issues, check the project repository or Sentry community forums.