package Sentry::Hub;
use Mojo::Base -base, -signatures;

use Mojo::Util 'dumper';
use Sentry::Hub::Scope;
use Sentry::Logger;
use Sentry::Severity;
use Sentry::Tracing::SamplingMethod;
use Sentry::Tracing::Transaction;
use Sentry::Util qw(uuid4);
use Time::HiRes  qw(time);
use Try::Tiny;

my $Instance;

has _last_event_id => undef;
has _stack         => sub { [{}] };
has client         => undef;
has scopes         => sub { [Sentry::Hub::Scope->new] };

sub init ($package, $options) {
  $Instance = Sentry::Hub->new($options);
}

sub reset ($self) {
  $self->scopes([Sentry::Hub::Scope->new]);
}

sub bind_client ($self, $client) {
  $self->client($client);
  $client->setup_integrations() if $client;
}

sub get_current_scope ($package) {
  return @{ $package->get_current_hub()->scopes }[-1];
}

sub get_current_hub {
  $Instance //= Sentry::Hub->new();
  return $Instance;
}

sub configure_scope ($self, $cb) {
  $cb->($self->get_current_scope);
}

sub push_scope ($self) {
  my $scope = $self->get_current_scope->clone;
  push $self->scopes->@*, $scope;
  return $scope;
}
sub pop_scope ($self) { pop @{ $self->scopes } }

sub with_scope ($self, $cb) {
  my $scope = $self->push_scope;

  try {
    $cb->($scope);
  } finally {
    $self->pop_scope;
  };
}

sub get_scope ($self) {
  return $self->get_current_scope;
}

sub _invoke_client ($self, $method, @args) {
  my $client = $self->client or return;
  my $scope  = $self->get_current_scope;

  if ($client->can($method)) {
    $client->$method(@args, $scope);
  } else {
    warn "Unknown method: $method";
  }
}

sub _new_event_id ($self) {
  $self->_last_event_id(uuid4());
  return $self->_last_event_id;
}

sub capture_message ($self, $message, $level = undef, $hint = undef,) {
  $level //= Sentry::Severity->Info;
  my $event_id = $self->_new_event_id();

  $self->_invoke_client('capture_message', $message, $level,
    { ($hint // {})->%*, event_id => $event_id });

  return $event_id;
}

sub capture_exception ($self, $exception, $hint = undef) {
  $hint //= {};
  my $event_id = $self->_new_event_id();

  $hint->{original_exception} = $exception;

  $self->_invoke_client('capture_exception', $exception,
    { $hint->%*, event_id => $event_id });

  return $event_id;
}

sub capture_event ($self, $event, $hint = undef) {
  my $event_id = $self->_new_event_id();

  $self->_invoke_client('capture_event', $event,
    { ($hint // {})->%*, event_id => $event_id });

  return $event_id;
}

sub add_breadcrumb ($self, $crumb, $hint = undef) {
  $self->get_current_scope->add_breadcrumb($crumb);
}

sub run ($self, $cb) {
  $cb->($self);
}

sub sample ($self, $transaction, $sampling_context) {
  my $client  = $self->client or return;
  my $options = ($client && $client->get_options) // {};

  # If the user has forced a sampling decision by passing a `sampled` value in
  # their transaction context, go with that
  if (defined $transaction->sampled) {
    $transaction->tags({
      $transaction->tags->%*,
      __sentry_samplingMethod => Sentry::Tracing::SamplingMethod->Explicit,
    });

    return $self->_finalize_sampling($transaction);
  }

  my $sample_rate;
  my $sampling_method;

  # Build the full sampling context for the traces_sampler callback
  my $full_sampling_context = {
    transaction_context => {
      name => $transaction->name,
      op   => $transaction->op,
    },
    parent_sampled => $sampling_context->{parent_sampled},
    %{$sampling_context // {}},
  };

  # Priority 1: traces_sampler callback (if defined)
  if (my $traces_sampler = $options->{traces_sampler}) {
    if (ref($traces_sampler) eq 'CODE') {
      my $sampler_result = eval { $traces_sampler->($full_sampling_context) };

      if ($@) {
        Sentry::Logger->logger->error(
          "traces_sampler threw an error: $@",
          { component => 'Tracing' }
        );
        # Fall through to other sampling methods
      } elsif (defined $sampler_result) {
        # Sampler returned a value - use it
        $sample_rate = $sampler_result;
        $sampling_method = 'traces_sampler';

        $transaction->tags({
          $transaction->tags->%*,
          __sentry_samplingMethod => 'traces_sampler',
          __sentry_sampleRate     => $sample_rate,
        });
      }
      # If sampler returned undef, fall through to other methods
    }
  }

  # Priority 2: Inherited sampling from parent (if no sampler decision)
  if (!defined $sample_rate && defined $sampling_context->{parent_sampled}) {
    $sample_rate = $sampling_context->{parent_sampled};
    $sampling_method = 'inheritance';

    $transaction->tags({
      $transaction->tags->%*,
      __sentry_samplingMethod => Sentry::Tracing::SamplingMethod->Inheritance,
    });
  }

  # Priority 3: traces_sample_rate (fallback)
  if (!defined $sample_rate) {
    $sample_rate = $options->{traces_sample_rate};
    $sampling_method = 'client_rate';

    if ($sample_rate) {
      $transaction->tags({
        $transaction->tags->%*,
        __sentry_samplingMethod => Sentry::Tracing::SamplingMethod->Rate,
        __sentry_sampleRate     => $sample_rate,
      });
    }
  }

  # No sample rate means tracing is disabled
  if (!$sample_rate) {
    Sentry::Logger->logger->debug(
      'Discarding transaction because tracing is disabled (no traces_sample_rate or traces_sampler)',
      { component => 'Tracing' }
    );
    $transaction->sampled(0);
    return $transaction;
  }

  # Make the sampling decision
  # If sample_rate is exactly 1 (or truthy boolean), always sample
  # Otherwise, roll the dice
  if ($sample_rate >= 1) {
    $transaction->sampled(1);
  } elsif ($sample_rate <= 0) {
    $transaction->sampled(0);
  } else {
    $transaction->sampled(rand() < $sample_rate);
  }

  # If we're not going to keep it, we're done
  if (!$transaction->sampled) {
    Sentry::Logger->logger->debug(
      "Discarding transaction because it's not included in the random sample (sampling rate = $sample_rate, method = $sampling_method)",
      { component => 'Tracing' }
    );
    return $transaction;
  }

  return $self->_finalize_sampling($transaction);
}

sub _finalize_sampling ($self, $transaction) {
  Sentry::Logger->logger->debug(
    sprintf(
      'Starting %s transaction - %s',
      $transaction->op // '(unknown op)',
      $transaction->name
    ),
    { component => 'Tracing' }
  );

  # Start profiling if transaction is sampled
  if ($transaction->sampled && $transaction->can('start_profiling')) {
    $transaction->start_profiling();
  }

  return $transaction;
}

sub start_transaction ($self, $context, $custom_sampling_context = {}) {
  my $transaction = Sentry::Tracing::Transaction->new(
    { $context->%*, _hub => $self, start_timestamp => time });

  return $self->sample(
    $transaction,
    {
      parent_sampled => $context->{parent_sampled},
      ($custom_sampling_context // {})->%*,
    }
  );
}

1;
