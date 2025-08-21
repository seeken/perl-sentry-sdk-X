# NAME

Sentry::SDK - sentry.io integration

# SYNOPSIS

    use Sentry::SDK;

    Sentry::SDK->init({
      dsn => "https://examplePublicKey@o0.ingest.sentry.io/0",

      # Adjust this value in production
      traces_sample_rate => 1.0,
    });

# DESCRIPTION

# FUNCTIONS

## init

    Sentry::SDK->init(\%options);

Initializes the Sentry SDK in your app. The following options are provided:

### dsn

The DSN tells the SDK where to send the events. If this value is not provided, the SDK will try to read it from the `SENTRY_DSN` environment variable. If that variable also does not exist, the SDK will just not send any events.

### release

Sets the release. Defaults to the `SENTRY_RELEASE` environment variable.

### environment

Sets the environment. This string is freeform and not set by default. A release can be associated with more than one environment to separate them in the UI (think staging vs prod or similar).

By default the SDK will try to read this value from the `SENTRY_ENVIRONMENT` environment variable.

### traces\_sample\_rate

A number between 0 and 1, controlling the percentage chance a given transaction will be sent to Sentry. (0 represents 0% while 1 represents 100%.) Applies equally to all transactions created in the app. This must be defined to enable tracing.

### profiles\_sample\_rate

A number between 0 and 1, controlling the percentage chance profiling data will be collected for transactions. (0 represents 0% while 1 represents 100%.) This setting requires that tracing also be enabled (`traces_sample_rate` > 0).

### enable\_profiling

Boolean flag to enable continuous profiling support. When enabled along with `profiles_sample_rate`, the SDK will collect stack traces at regular intervals to provide code-level performance insights. Defaults to `false`.

### sampling\_interval\_us

The interval in microseconds between profiling samples. Lower values provide more detailed profiles but increase overhead. Defaults to 10,000 microseconds (10ms). Common values:

- 1000 (1ms): High detail, high overhead - for development only  
- 5000 (5ms): Good balance for staging environments
- 10000 (10ms): Production-ready with minimal overhead

### adaptive\_sampling

Enable adaptive sampling that adjusts the sampling frequency based on system load. When enabled, the profiler will automatically reduce sampling during high CPU or memory usage periods. Defaults to `false`.

### profile\_lifecycle

Controls when profiling is active:

- `manual`: Only when explicitly started/stopped via SDK methods
- `trace`: Automatically profile during transactions (default)
- `continuous`: Always active when profiling is enabled

### Additional Profiling Options

Advanced profiling configuration options:

    Sentry::SDK->init({
      enable_profiling => 1,
      profiles_sample_rate => 0.1,
      
      # System resource thresholds for adaptive sampling
      cpu_threshold_percent => 70,      # Reduce sampling if CPU > 70%
      memory_threshold_mb => 100,       # Reduce sampling if memory > 100MB
      
      # Frame collection limits
      max_stack_depth => 50,            # Maximum stack frames per sample  
      max_frames_per_sample => 200,     # Maximum unique frames per sample
      
      # Package filtering
      ignore_packages => ['Test::', 'DBI', 'JSON::'],  # Skip these packages
    });

### before\_send

    Sentry::SDK->init({
      before_send => sub ($event, $hint) {

        # discard event we don't care about
        if (ref($hint->{original_exception}) eq 'My::Ignorable::Exception') {
          return undef;
        }

        # add a custom tag otherwise
        $event->tags->{foo} = 'bar';

        return $event;
      };
    });

`beforeSend` is called immediately before the event is sent to the server, so it’s the final place where you can edit its data. It receives the event object as a parameter, so you can use that to modify the event’s data or drop it completely (by returning `undef`) based on custom logic and the data available on the event.

### integrations

    Sentry::SDK->init({
      integrations => [My::Integration->new],
    });

Enables your custom integration. Optional.

### default\_integrations

This can be used to disable integrations that are added by default. When set to a falsy value, no default integrations are added.

### debug

Enables debug printing.

## add\_breadcrumb

    Sentry::SDK->add_breadcrumb({
      category => "auth",
      message => "Authenticated user " . user->{email},
      level => Sentry::Severity->Info,
    });

You can manually add breadcrumbs whenever something interesting happens. For example, you might manually record a breadcrumb if the user authenticates or another state change happens.

## capture\_exception

    eval {
      $app->run();
    };
    if ($@) {
      Sentry::SDK->capture_exception($@);
    }

You can pass an error object to capture\_exception() to get it captured as event. It's possible to throw strings as errors.

## capture\_message

    Sentry::SDK->capture_message("Something went wrong");

Another common operation is to capture a bare message. A message is textual information that should be sent to Sentry. Typically messages are not emitted, but they can be useful for some teams.

## capture\_event

    Sentry::SDK->capture_event(\%data);

Captures a manually created event and sends it to Sentry.

## configure\_scope

    Sentry::SDK->configure_scope(sub ($scope) {
      $scope->set_tag(foo => "bar");
      $scope->set_user({id => 1, email => "john.doe@example.com"});
    });

When an event is captured and sent to Sentry, event data with extra information will be merged from the current scope. The `configure_scope` function can be used to reconfigure the current scope. This for instance can be used to add custom tags or to inform sentry about the currently authenticated user. See [Sentry::Hub::Scope](https://metacpan.org/pod/Sentry%3A%3AHub%3A%3AScope) for further information.

## start\_transaction

    my $transaction = Sentry::SDK->start_transaction({
      name => 'MyScript',
      op => 'http.server',
    });

    Sentry::SDK->configure_scope(sub ($scope) {
      $scope->set_span($transaction);
    });

    # ...

    $transaction->set_http_status(200);
    $transaction->finish();

Is needed for recording tracing information. Transactions are usually handled by the respective framework integration. See [Sentry::Tracing::Transaction](https://metacpan.org/pod/Sentry%3A%3ATracing%3A%3ATransaction).

## start\_profiler

    my $profile = Sentry::SDK->start_profiler({
      name => 'background_task'
    });
    
    # ... do work ...
    
    my $stopped_profile = Sentry::SDK->stop_profiler();

Manually starts profiling for the current context. Returns a profile object that will collect stack traces until `stop_profiler()` is called. Most useful with `profile_lifecycle => 'manual'` setting.

## stop\_profiler

    my $profile = Sentry::SDK->stop_profiler();

Stops the currently active profiling session and returns the completed profile. The profile data is automatically sent to Sentry unless profiling was disabled.

## profile

    my $result = Sentry::SDK->profile(sub {
      # Code to be profiled
      expensive_computation();
      return "result";
    });

Convenience method that profiles the execution of a code block. Automatically handles starting and stopping the profiler around the provided subroutine.

## get\_profiler

    my $profiler = Sentry::SDK->get_profiler();
    if ($profiler && $profiler->is_active()) {
      my $stats = $profiler->get_active_profile()->get_stats();
      say "Profile has " . $stats->{sample_count} . " samples";
    }

Returns the current profiler instance, allowing access to profiling state and statistics. Useful for monitoring profiling overhead and status.

### Profiling Usage Examples

Basic profiling with transactions:

    use Sentry::SDK;
    
    Sentry::SDK->init({
      dsn => $ENV{SENTRY_DSN},
      traces_sample_rate => 1.0,
      profiles_sample_rate => 0.1,  # Profile 10% of transactions
      enable_profiling => 1,
    });
    
    # Automatic profiling during transactions
    my $transaction = Sentry::SDK->start_transaction({
      name => 'data_processing',
      op => 'task',
    });
    
    process_data();  # This will be profiled
    
    $transaction->finish();

Manual profiling control:

    # Start profiling manually
    my $profile = Sentry::SDK->start_profiler({ 
      name => 'custom_analysis' 
    });
    
    perform_analysis();
    
    # Stop and get profile stats
    my $completed = Sentry::SDK->stop_profiler();
    my $stats = $completed->get_stats();
    
    say "Collected " . $stats->{sample_count} . " samples";
    say "Found " . $stats->{unique_frames} . " unique frames";

Profiling with adaptive sampling:

    Sentry::SDK->init({
      enable_profiling => 1,
      profiles_sample_rate => 1.0,
      adaptive_sampling => 1,
      cpu_threshold_percent => 80,
      sampling_interval_us => 5000,  # 5ms base interval
    });

For more examples, see the `examples/advanced_profiling_demo.pl` and `examples/profiling_benchmark.pl` files included with the SDK.

# AUTHOR

Philipp Busse <pmb@heise.de>

# COPYRIGHT

Copyright 2021- Philipp Busse

# LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# SEE ALSO
