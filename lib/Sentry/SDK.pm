package Sentry::SDK;
use Mojo::Base -base, -signatures;

use version 0.77;
use Mojo::Util 'dumper';
use Sentry::Client;
use Sentry::Hub;
use Sentry::Logger;

our $VERSION = version->declare('1.3.9');

sub _call_on_hub ($method, @args) {
  my $hub = Sentry::Hub->get_current_hub();

  if (my $cb = $hub->can($method)) {
    return $cb->($hub, @args);
  }

  die
    "No hub defined or $method was not found on the hub, please open a bug report.";
}

sub _init_and_bind ($options) {
  my $hub = Sentry::Hub->get_current_hub();
  my $client
    = ($options->{dsn} && $options->{dsn} ne '') ? Sentry::Client->new(_options => $options) : undef;
  
  # Always bind the client (even if it's undef) to clear any existing client
  # bind_client will call setup_integrations if client is defined
  $hub->bind_client($client);
}

sub init ($package, $options = {}) {
  # Set environment variables first
  $options->{dsn}                  //= $ENV{SENTRY_DSN};
  $options->{traces_sample_rate}   //= $ENV{SENTRY_TRACES_SAMPLE_RATE};
  $options->{release}              //= $ENV{SENTRY_RELEASE};
  $options->{environment}          //= $ENV{SENTRY_ENVIRONMENT};
  $options->{_metadata}            //= {};
  $options->{_metadata}{sdk}
    = { name => 'sentry.perl', packages => [], version => $VERSION };

  # Only set up integrations if we have a valid DSN that can be parsed
  my $has_valid_dsn = 0;
  if ($options->{dsn} && $options->{dsn} ne '') {
    eval {
      require Sentry::DSN;
      Sentry::DSN->parse($options->{dsn});
      $has_valid_dsn = 1;
    };
  }
  
  if ($has_valid_dsn) {
    # Set default integrations if not explicitly disabled
    $options->{default_integrations} //= 1;
    $options->{integrations} //= [];
    
    # Add built-in integrations unless disabled
    if ($options->{default_integrations}) {
      # Allow selective disabling of built-in integrations
      my %disabled = map { $_ => 1 } @{$options->{disabled_integrations} // []};
      
      # Import integration modules
      require Sentry::Integration::DieHandler;
      require Sentry::Integration::DBI;
      require Sentry::Integration::LwpUserAgent;
      require Sentry::Integration::MojoUserAgent;
      require Sentry::Integration::MojoTemplate;
      
      unless ($disabled{DieHandler}) {
        push @{$options->{integrations}}, Sentry::Integration::DieHandler->new;
      }
      unless ($disabled{DBI}) {
        push @{$options->{integrations}}, Sentry::Integration::DBI->new;
      }
      unless ($disabled{LwpUserAgent}) {
        push @{$options->{integrations}}, Sentry::Integration::LwpUserAgent->new;
      }
      unless ($disabled{MojoUserAgent}) {
        push @{$options->{integrations}}, Sentry::Integration::MojoUserAgent->new;
      }
      unless ($disabled{MojoTemplate}) {
        push @{$options->{integrations}}, Sentry::Integration::MojoTemplate->new;
      }
    }
    
    # Set enhanced client option defaults only when we have a valid DSN
    $options->{max_request_body_size}     //= 'medium';
    $options->{max_attachment_size}       //= 20 * 1024 * 1024;  # 20MB
    $options->{send_default_pii}          //= 0;
    $options->{capture_failed_requests}   //= 0;
    $options->{failed_request_status_codes} //= [500..599];
    $options->{failed_request_targets}    //= ['.*'];
    $options->{ignore_errors}             //= [];
    $options->{ignore_transactions}       //= [];
    $options->{enable_tracing}            //= 1;
    $options->{profiles_sample_rate}      //= 0;
    $options->{enable_profiling}          //= 0;
    $options->{offline_storage_path}      //= undef;
    $options->{max_offline_events}        //= 100;
    $options->{max_queue_size}            //= 100;
    $options->{auto_session_tracking}     //= 0;
    $options->{enable_logs}               //= 1;  # Enable structured logging by default
    $options->{_experiments}              //= {};
    
    # Add structured logging to experiments if enable_logs is true
    if ($options->{enable_logs}) {
      $options->{_experiments}{enable_logs} = 1;
    }
  } else {
    # No valid DSN means no integrations or enhanced options
    $options->{default_integrations} //= 1;  # Keep default behavior for tests
    $options->{integrations} //= [];
  }


  _init_and_bind($options);
}

sub capture_message ($self, $message, $capture_context = undef) {
  my $level = ref($capture_context) ? undef : $capture_context;

  _call_on_hub('capture_message', $message, $level,
    { capture_context => ref($capture_context) ? $capture_context : undef, });
}

sub capture_event ($package, $event, $capture_context = undef) {
  _call_on_hub('capture_event', $event,
    { capture_context => ref($capture_context) ? $capture_context : undef, });
}

sub capture_exception ($package, $exception, $capture_context = undef) {
  _call_on_hub('capture_exception', $exception,
    { capture_context => ref($capture_context) ? $capture_context : undef, });
}

sub configure_scope ($package, $cb) {
  Sentry::Hub->get_current_hub()->configure_scope($cb);
}

sub add_breadcrumb ($package, $crumb) {
  Sentry::Hub->get_current_hub()->add_breadcrumb($crumb);
}

sub start_transaction ($package, $context, $custom_sampling_context = undef) {
  return _call_on_hub('start_transaction', $context, $custom_sampling_context);
}

# Cron monitoring methods

sub capture_check_in ($package, $options = {}) {
  require Sentry::Crons;
  return Sentry::Crons->capture_check_in($options);
}

sub update_check_in ($package, $check_in_id, $status, $duration_ms = undef) {
  require Sentry::Crons;
  return Sentry::Crons->update_check_in($check_in_id, $status, $duration_ms);
}

sub with_monitor ($package, $monitor_slug, $coderef, $options = {}) {
  require Sentry::Crons;
  return Sentry::Crons->with_monitor($monitor_slug, $coderef, $options);
}

sub upsert_monitor ($package, $monitor_config) {
  require Sentry::Crons;
  return Sentry::Crons->upsert_monitor($monitor_config);
}

# Structured logging methods
sub get_logger ($package) {
  require Sentry::Logger;
  return Sentry::Logger->logger();
}

sub log ($package, $level, $message, $context = {}) {
  require Sentry::Logger;
  return Sentry::Logger->logger->log($level, $message, $context);
}

sub logf ($package, $level, $template, @args) {
  require Sentry::Logger;
  return Sentry::Logger->logger->logf($level, $template, @args);
}

sub log_trace ($package, $message, $context = {}) {
  require Sentry::Logger;
  return Sentry::Logger->logger->trace($message, $context);
}

sub log_debug ($package, $message, $context = {}) {
  require Sentry::Logger;
  return Sentry::Logger->logger->debug($message, $context);
}

sub log_info ($package, $message, $context = {}) {
  require Sentry::Logger;
  return Sentry::Logger->logger->info($message, $context);
}

sub log_warn ($package, $message, $context = {}) {
  require Sentry::Logger;
  return Sentry::Logger->logger->warn($message, $context);
}

sub log_error ($package, $message, $context = {}) {
  require Sentry::Logger;
  return Sentry::Logger->logger->error($message, $context);
}

sub log_fatal ($package, $message, $context = {}) {
  require Sentry::Logger;
  return Sentry::Logger->logger->fatal($message, $context);
}

sub log_exception ($package, $exception, $level = 'error', $context = {}) {
  require Sentry::Logger;
  return Sentry::Logger->logger->log_exception($exception, $level, $context);
}

sub with_log_context ($package, $context) {
  require Sentry::Logger;
  return Sentry::Logger->logger->with_context($context);
}

sub flush_logs ($package) {
  require Sentry::Logger;
  return Sentry::Logger->logger->flush();
}

sub get_last_event_id ($package) {
  my $hub = Sentry::Hub->get_current_hub();
  return $hub->last_event_id() if $hub->can('last_event_id');
  return undef;
}

1;

__END__

=encoding utf-8

=head1 NAME

Sentry::SDK - sentry.io integration

=head1 SYNOPSIS

  use Sentry::SDK;

  Sentry::SDK->init({
    dsn => "https://examplePublicKey@o0.ingest.sentry.io/0",

    # Adjust this value in production
    traces_sample_rate => 1.0,
  });

=head1 DESCRIPTION

=head1 FUNCTIONS

=head2 init

  Sentry::SDK->init(\%options);

Initializes the Sentry SDK in your app. The following options are provided:

=head3 dsn

The DSN tells the SDK where to send the events. If this value is not provided, the SDK will try to read it from the C<SENTRY_DSN> environment variable. If that variable also does not exist, the SDK will just not send any events.

=head3 release

Sets the release. Defaults to the C<SENTRY_RELEASE> environment variable.

=head3 environment

Sets the environment. This string is freeform and not set by default. A release can be associated with more than one environment to separate them in the UI (think staging vs prod or similar).

By default the SDK will try to read this value from the C<SENTRY_ENVIRONMENT> environment variable.

=head3 traces_sample_rate

A number between 0 and 1, controlling the percentage chance a given transaction will be sent to Sentry. (0 represents 0% while 1 represents 100%.) Applies equally to all transactions created in the app. This must be defined to enable tracing.

=head3 before_send

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

C<beforeSend> is called immediately before the event is sent to the server, so it’s the final place where you can edit its data. It receives the event object as a parameter, so you can use that to modify the event’s data or drop it completely (by returning C<undef>) based on custom logic and the data available on the event.

=head3 integrations

  Sentry::SDK->init({
    integrations => [My::Integration->new],
  });

Enables your custom integration. Optional.

=head3 default_integrations

This can be used to disable integrations that are added by default. When set to a falsy value, no default integrations are added.

=head3 debug

Enables debug printing.

=head2 add_breadcrumb

  Sentry::SDK->add_breadcrumb({
    category => "auth",
    message => "Authenticated user " . user->{email},
    level => Sentry::Severity->Info,
  });

You can manually add breadcrumbs whenever something interesting happens. For example, you might manually record a breadcrumb if the user authenticates or another state change happens.

=head2 capture_exception

  eval {
    $app->run();
  };
  if ($@) {
    Sentry::SDK->capture_exception($@);
  }

You can pass an error object to capture_exception() to get it captured as event. It's possible to throw strings as errors.

=head2 capture_message

  Sentry::SDK->capture_message("Something went wrong");

Another common operation is to capture a bare message. A message is textual information that should be sent to Sentry. Typically messages are not emitted, but they can be useful for some teams.

=head2 capture_event

  Sentry::SDK->capture_event(\%data);

Captures a manually created event and sends it to Sentry.

=head2 configure_scope

  Sentry::SDK->configure_scope(sub ($scope) {
    $scope->set_tag(foo => "bar");
    $scope->set_user({id => 1, email => "john.doe@example.com"});
  });

When an event is captured and sent to Sentry, event data with extra information will be merged from the current scope. The C<configure_scope> function can be used to reconfigure the current scope. This for instance can be used to add custom tags or to inform sentry about the currently authenticated user. See L<Sentry::Hub::Scope> for further information.

=head2 start_transaction

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

Is needed for recording tracing information. Transactions are usually handled by the respective framework integration. See L<Sentry::Tracing::Transaction>.

=head2 capture_check_in

  my $check_in_id = Sentry::SDK->capture_check_in({
    monitor_slug => 'daily-backup',
    status => 'in_progress',
    environment => 'production',
  });

  # Later, update the check-in
  Sentry::SDK->update_check_in($check_in_id, 'ok', 30000);

Captures a cron job check-in for monitoring scheduled tasks. The check-in can be updated later with completion status and duration.

=head2 with_monitor

  Sentry::SDK->with_monitor('daily-backup', sub {
    # Your cron job code here
    perform_backup();
  });

Wraps code execution with automatic cron monitoring. Creates a check-in before execution and updates it with the result automatically.

=head2 upsert_monitor

  Sentry::SDK->upsert_monitor({
    slug => 'daily-backup',
    name => 'Daily Database Backup',
    schedule => {
      type => 'crontab',
      value => '0 2 * * *',  # Daily at 2 AM
    },
    checkin_margin => 10,  # minutes
    max_runtime => 60,     # minutes
    timezone => 'UTC',
  });

Creates or updates a monitor configuration in Sentry for scheduled job monitoring.

=head2 get_logger

  my $logger = Sentry::SDK->get_logger();

Returns the singleton structured logger instance for direct use.

=head2 log

  Sentry::SDK->log('info', 'User action completed', { user_id => 123 });

Core structured logging method. Supports levels: trace, debug, info, warn, error, fatal.

=head2 logf

  Sentry::SDK->logf('info', 'Processing %d items', $count, { batch_id => $id });

Template-based logging with sprintf formatting. Last argument can be a context hash.

=head2 log_trace, log_debug, log_info, log_warn, log_error, log_fatal

  Sentry::SDK->log_info('Operation completed', { duration_ms => 150 });
  Sentry::SDK->log_error('Database error', { table => 'users', error => $@ });

Convenience methods for different log levels with structured context.

=head2 log_exception

  Sentry::SDK->log_exception($@, 'error', { operation => 'save_user' });

Logs exceptions with automatic stacktrace extraction and context enrichment.

=head2 with_log_context

  my $contextual_logger = Sentry::SDK->with_log_context({ request_id => $id });
  $contextual_logger->info('Request processed');

Returns a logger instance with additional context that will be included in all subsequent log entries.

=head2 flush_logs

  my $count = Sentry::SDK->flush_logs();

Manually flushes any buffered log records to Sentry and returns the number of records sent.

=head1 AUTHOR

Philipp Busse E<lt>pmb@heise.deE<gt>

=head1 COPYRIGHT

Copyright 2021- Philipp Busse

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

=cut
