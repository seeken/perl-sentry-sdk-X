package Sentry::Tracing::Transaction;
use Mojo::Base 'Sentry::Tracing::Span', -signatures;

# https://develop.sentry.dev/sdk/unified-api/tracing

use Mojo::Util 'dumper';

has _hub        => undef;
has sampled     => undef;
has context     => undef;
has name        => '<unlabeled transaction>';
has spans       => sub { [] };
has transaction => sub ($self) {$self};
has _profile    => undef;  # Associated profile

sub start_profiling ($self) {
  return unless $self->_hub;
  
  my $client = $self->_hub->client;
  return unless $client && $client->profiler;
  
  # Start profiling if enabled and sampled
  if ($self->sampled && $client->profiler->enable_profiling) {
    my $profile = $client->profiler->start_transaction_profiling($self);
    $self->_profile($profile);
  }
}

sub finish ($self) {
  # Stop profiling if active
  if ($self->_profile) {
    my $client = $self->_hub->client;
    if ($client && $client->profiler) {
      $client->profiler->stop_profiler();
    }
  }
  
  $self->SUPER::finish();

  return unless $self->sampled;

  my %transaction = (
    contexts        => { trace => $self->get_trace_context(), },
    spans           => $self->_collect_spans(),
    start_timestamp => $self->start_timestamp,
    tags            => $self->tags,
    timestamp       => $self->timestamp,
    transaction     => $self->name,
    request         => $self->request,
    type            => 'transaction',
  );

  $self->_hub->capture_event(\%transaction);
}

sub set_name ($self, $name) {
  $self->name($name);
}

1;
