package Sentry::Client;
use Mojo::Base -base, -signatures;

use Mojo::Exception;
use Mojo::Home;
use Mojo::Util 'dumper';
use Sentry::DSN;
use Sentry::Hub::Scope;
use Sentry::Integration;
use Sentry::Logger 'logger';
use Sentry::SourceFileRegistry;
use Sentry::Stacktrace;
use Sentry::Transport::Http;
use Sentry::Util qw(uuid4 truncate);
use Time::HiRes;
use Try::Tiny;
use File::Spec;
use JSON::PP;
use POSIX qw(strftime);

has _dsn     => sub ($self) { Sentry::DSN->parse($self->_options->{dsn}) };
has _options => sub { {} };
has _transport =>
  sub ($self) { Sentry::Transport::Http->new(dsn => $self->_dsn) };
has scope        => sub { Sentry::Hub::Scope->new };
has integrations => sub ($self) { $self->_options->{integrations} // [] };

sub setup_integrations ($self) {
  Sentry::Integration->setup($self->integrations);
}

# Enhanced client configuration methods
sub should_ignore_error ($self, $error) {
  my $ignore_patterns = $self->_options->{ignore_errors} // [];
  
  for my $pattern (@$ignore_patterns) {
    if (ref($pattern) eq 'Regexp') {
      return 1 if $error =~ $pattern;
    } elsif (ref($pattern) eq 'CODE') {
      return 1 if $pattern->($error);
    } else {
      return 1 if index($error, $pattern) >= 0;
    }
  }
  
  return 0;
}

sub should_ignore_transaction ($self, $transaction_name) {
  my $ignore_patterns = $self->_options->{ignore_transactions} // [];
  
  for my $pattern (@$ignore_patterns) {
    if (ref($pattern) eq 'Regexp') {
      return 1 if $transaction_name =~ $pattern;
    } elsif (ref($pattern) eq 'CODE') {
      return 1 if $pattern->($transaction_name);
    } else {
      return 1 if index($transaction_name, $pattern) >= 0;
    }
  }
  
  return 0;
}

sub should_capture_failed_request ($self, $status_code, $url = undef) {
  return 0 unless $self->_options->{capture_failed_requests};
  
  # Check status codes
  my $failed_codes = $self->_options->{failed_request_status_codes} // [500..599];
  my $status_matches = 0;
  
  for my $code (@$failed_codes) {
    if (ref($code) eq 'ARRAY') {
      $status_matches = 1 if $status_code >= $code->[0] && $status_code <= $code->[1];
    } else {
      $status_matches = 1 if $status_code == $code;
    }
    last if $status_matches;
  }
  
  return 0 unless $status_matches;
  
  # Check URL patterns if URL provided
  if ($url) {
    my $target_patterns = $self->_options->{failed_request_targets} // ['.*'];
    my $url_matches = 0;
    
    for my $pattern (@$target_patterns) {
      if (ref($pattern) eq 'Regexp') {
        $url_matches = 1 if $url =~ $pattern;
      } else {
        $url_matches = 1 if $url =~ qr/$pattern/;
      }
      last if $url_matches;
    }
    
    return $url_matches;
  }
  
  return 1;
}

sub get_max_request_body_size ($self) {
  my $size = $self->_options->{max_request_body_size} // 'medium';
  
  return $size if $size =~ /^\d+$/;
  
  return {
    never  => 0,
    always => -1,
    small  => 10 * 1024,      # 10KB
    medium => 100 * 1024,     # 100KB
    large  => 1024 * 1024,    # 1MB
  }->{$size} // 100 * 1024;
}

sub store_offline_event ($self, $event) {
  my $offline_path = $self->_options->{offline_storage_path};
  return unless $offline_path;
  
  eval {
    # Create directory if it doesn't exist
    unless (-d $offline_path) {
      require File::Path;
      File::Path::make_path($offline_path);
    }
    
    # Check max offline events limit
    my $max_events = $self->_options->{max_offline_events} // 100;
    my @existing_files = glob(File::Spec->catfile($offline_path, "sentry_event_*.json"));
    
    if (@existing_files >= $max_events) {
      # Remove oldest files
      @existing_files = sort @existing_files;
      my $to_remove = @existing_files - $max_events + 1;
      unlink splice(@existing_files, 0, $to_remove);
    }
    
    # Store event
    my $timestamp = strftime("%Y%m%d_%H%M%S", localtime);
    my $filename = File::Spec->catfile($offline_path, "sentry_event_${timestamp}_$$.json");
    
    open my $fh, '>', $filename or die "Cannot open $filename: $!";
    print $fh JSON::PP->new->ascii->pretty->encode($event);
    close $fh;
    
    logger()->debug("Stored offline event: $filename");
  };
  
  if ($@) {
    logger()->error("Failed to store offline event: $@");
  }
}

#  (alternatively normal constructor) This takes typically an object with options + dsn.
sub from_config ($package, $config) { }

sub event_from_message (
  $self, $message,
  $level = Sentry::Severity->Info,
  $hint = undef
) {
  my %event = (
    event_id => $hint && $hint->{event_id},
    level    => $level,
    message  => $message,
  );

  return \%event;
}

sub capture_message (
  $self, $message,
  $level = undef,
  $hint  = undef,
  $scope = undef
) {
  my $event = $self->event_from_message($message, $level, $hint);

  return $self->_capture_event($event, $hint, $scope);
}

sub capture_event ($self, $event, $hint = undef, $scope = undef) {
  my $event_id = ($hint // {})->{event_id};

  return $self->_capture_event($event, $hint, $scope);
}

sub event_from_exception ($self, $exception, $hint = undef, $scope = undef) {
  if (!ref($exception)) {
    $exception = Mojo::Exception->new($exception)->trace;
  }

  my $stacktrace = Sentry::Stacktrace->new({
    exception    => $exception,
    frame_filter => sub ($frame) {
      $frame->module !~ m{^(Sentry::.*|Class::MOP|CGI::Carp|Try::Tiny)$};
    },
  });

  return {
    event_id  => $hint && $hint->{event_id},
    level     => ($hint && $hint->{level}) || Sentry::Severity->Error,
    exception => {
      values => [{
        type  => ref($exception),
        value => $exception->can('to_string')
        ? $exception->to_string
        : $exception,
        module     => ref($exception),
        stacktrace => $stacktrace,
      }]
    }
  };
}

sub capture_exception ($self, $exception, $hint = undef, $scope = undef) {
  my $event = $self->event_from_exception($exception, $hint);

  return $self->_capture_event($event, $hint, $scope);
}

sub _capture_event ($self, $event, $hint = undef, $scope = undef) {
  my $event_id;

  try {
    # Check if error should be ignored
    my $error_msg = '';
    if ($event->{exception}) {
      $error_msg = ref($event->{exception}) eq 'HASH' 
        ? ($event->{exception}->{values}->[0]->{value} // '')
        : "$event->{exception}";
    } elsif ($event->{message}) {
      $error_msg = ref($event->{message}) eq 'HASH'
        ? ($event->{message}->{formatted} // $event->{message}->{message} // '')
        : "$event->{message}";
    }
    
    if ($error_msg && $self->should_ignore_error($error_msg)) {
      logger()->debug("Ignoring error due to ignore_errors configuration: $error_msg");
      return;
    }
    
    # Check if transaction should be ignored
    if ($event->{transaction} && $self->should_ignore_transaction($event->{transaction})) {
      logger()->debug("Ignoring transaction due to ignore_transactions configuration: $event->{transaction}");
      return;
    }
    
    $event_id = $self->_process_event($event, $hint, $scope)->{event_id};
  } catch {
    logger->error($_);
    
    # Store offline if configured
    if ($self->_options->{offline_storage_path}) {
      $self->store_offline_event($event);
    }
  };

  return $event_id;
}

# Captures the event by merging it with other data with defaults from the
# client. In addition, if a scope is passed to this system, the data from the
# scope passes it to the internal transport.
# sub capture_event ($self, $event, $scope) { }

# Flushes out the queue for up to timeout seconds. If the client can guarantee
# delivery of events only up to the current point in time this is preferred.
# This might block for timeout seconds. The client should be disabled or
# disposed after close is called
sub close ($self, $timeout) { }

# Same as close difference is that the client is NOT disposed after calling flush
sub flush ($self, $timeout) { }

# Applies `normalize` function on necessary `Event` attributes to make them safe for serialization.
# Normalized keys:
# - `breadcrumbs.data`
# - `user`
# - `contexts`
# - `extra`
sub _normalize_event ($self, $event) {
  my %normalized = ($event->%*,);
  return \%normalized;
}

sub _apply_client_options ($self, $event) {
  my $options          = $self->_options;
  my $max_value_length = $options->{max_value_length} // 250;

  $event->{environment} //= $options->{environment} // 'production';
  $event->{dist}        //= $options->{dist};
  $event->{release}     //= $options->{release} if $options->{release};

  $event->{message} = truncate($event->{message}, $max_value_length)
    if $event->{message};

  # Apply request body size limits
  if ($event->{request} && $event->{request}->{data}) {
    my $max_body_size = $self->get_max_request_body_size();
    
    if ($max_body_size == 0) {
      # Never capture request body
      delete $event->{request}->{data};
    } elsif ($max_body_size > 0) {
      # Limit request body size
      my $body_str = ref($event->{request}->{data}) ? 
        JSON::PP->new->encode($event->{request}->{data}) : 
        "$event->{request}->{data}";
      
      if (length($body_str) > $max_body_size) {
        $event->{request}->{data} = '[Request body too large]';
      }
    }
    # If max_body_size is -1 (always), keep the full body
  }
  
  # Handle PII scrubbing unless explicitly allowed
  unless ($options->{send_default_pii}) {
    $self->_scrub_pii($event);
  }

  return;
}

sub _scrub_pii ($self, $event) {
  # Scrub sensitive data from request headers
  if ($event->{request} && $event->{request}->{headers}) {
    my $headers = $event->{request}->{headers};
    
    for my $header (keys %$headers) {
      my $lower_header = lc($header);
      
      if ($lower_header =~ /^(authorization|cookie|x-api-key|x-auth-token|password|secret)$/) {
        $headers->{$header} = '[Filtered]';
      }
    }
  }
  
  # Scrub user email and username unless explicitly allowed
  if ($event->{user}) {
    for my $field (qw(email username ip_address)) {
      if (exists $event->{user}->{$field}) {
        $event->{user}->{$field} = '[Filtered]';
      }
    }
  }
  
  # Scrub sensitive context data
  if ($event->{extra}) {
    for my $key (keys %{$event->{extra}}) {
      if ($key =~ /^(password|secret|token|key|auth)/i) {
        $event->{extra}->{$key} = '[Filtered]';
      }
    }
  }
}

sub get_options ($self) {
  return $self->_options;
}

sub _apply_integrations_metadata ($self, $event) {
  $event->{sdk} //= {};

  my @integrations = $self->integrations->@*;
  $event->{sdk}->{integrations} = [map { ref($_) } @integrations]
    if @integrations;
}

# Adds common information to events.
#
# The information includes release and environment from `options`,
# breadcrumbs and context (extra, tags and user) from the scope.
#
# Information that is already present in the event is never overwritten. For
# nested objects, such as the context, keys are merged.
#
# @param event The original event.
# @param hint May contain additional information about the original exception.
# @param scope A scope containing event metadata.
# @returns A new event with more information.
sub _prepare_event ($self, $event, $scope, $hint = undef) {
  my %prepared = (
    $event->%*,
    sdk       => $self->_options->{_metadata}{sdk},
    platform  => 'perl',
    event_id  => $event->{event_id}  // ($hint // {})->{event_id} // uuid4(),
    timestamp => $event->{timestamp} // time,
  );

  $self->_apply_client_options(\%prepared);
  $self->_apply_integrations_metadata(\%prepared);

  # If we have scope given to us, use it as the base for further modifications.
  # This allows us to prevent unnecessary copying of data if `capture_context`
  # is not provided.
  my $final_scope = $scope;
  if (($hint // {})->{capture_context}) {
    $final_scope = $scope->clone()->update($hint->{capture_context});
  }

  # We prepare the result here with a resolved Event.
  my $result = \%prepared;
  # This should be the last thing called, since we want that
  # {@link Hub.addEventProcessor} gets the finished prepared event.
  if ($final_scope) {

    # In case we have a hub we reassign it.
    $result = $final_scope->apply_to_event(\%prepared, $hint);
  }

  return $self->_normalize_event($result);
}

sub _process_event ($self, $event, $hint, $scope) {
  my $prepared = $self->_prepare_event($event, $scope, $hint);

  my $before_send = $self->_options->{before_send}
    // sub ($event, $hint) {$event};

  my $processed_event = $before_send->($prepared, $hint // {});

  die 'An event processor returned undef, will not send event.'
    unless $processed_event;

  $self->_send_event($processed_event);

  return $processed_event;
}

sub _send_event ($self, $event) {
  $self->_transport->send($event);
  return;
}

sub _prepare_envelope ($self) {
  require Sentry::Envelope;
  
  return Sentry::Envelope->new(
    headers => {
      event_id => uuid4(),
      sent_at => strftime('%Y-%m-%dT%H:%M:%S.000Z', gmtime(time())),
      trace => {},
    }
  );
}

sub _send_envelope ($self, $envelope) {
  $self->_transport->send_envelope($envelope);
  return;
}

1;

