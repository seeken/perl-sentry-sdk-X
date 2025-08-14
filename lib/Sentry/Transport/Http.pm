package Sentry::Transport::Http;
use Mojo::Base -base, -signatures;

use HTTP::Status qw(:constants);
use Mojo::JSON 'encode_json';
use Mojo::UserAgent;
use Mojo::Util 'dumper';
use Readonly;
use Sentry::Envelope;
use Sentry::Hub;
use Sentry::Logger 'logger';
use Sentry::RateLimit;
use Sentry::Backpressure;

Readonly my $SENTRY_API_VERSION => '7';

has _http => sub {
  Mojo::UserAgent->new(request_timeout => 5, connect_timeout => 1);
};
has _sentry_client => 'perl-sentry/1.0';
has _headers       => sub ($self) {
  my @header = (
    "Sentry sentry_version=$SENTRY_API_VERSION",
    "sentry_client=" . $self->_sentry_client,
    'sentry_key=' . $self->dsn->user,
  );

  my $pass = $self->dsn->pass;
  push @header, "sentry_secret=$pass" if $pass;

  return {
    'Content-Type'  => 'application/json',
    'X-Sentry-Auth' => join(', ', @header),
  };
};
has _sentry_url => sub ($self) {
  my $dsn = $self->dsn;
  die 'DSN missing' unless $dsn;

  return
    sprintf('%s://%s/api/%d', $dsn->protocol, $dsn->host_port,
      $dsn->project_id);
};
has dsn => undef;
has rate_limit => sub { Sentry::RateLimit->new };
has backpressure => sub { Sentry::Backpressure->new };

sub send ($self, $payload) {
  return unless $self->dsn;
  
  # Determine event type for rate limiting
  my $event_type = 'error';
  if (ref($payload) eq 'HASH') {
    $event_type = $payload->{type} // 'error';
  } elsif (ref($payload) eq 'Sentry::Envelope') {
    # Check envelope items for type
    my @items = $payload->get_items();
    $event_type = $items[0]->{headers}{type} if @items;
  }
  
  # Check rate limits
  if ($self->rate_limit->is_rate_limited($event_type)) {
    my $retry_after = $self->rate_limit->get_retry_after($event_type);
    logger->warn("Rate limited for $event_type events, retry after $retry_after seconds");
    return;
  }
  
  # Check backpressure
  if ($self->backpressure->should_drop_event($event_type)) {
    $self->backpressure->record_dropped_event();
    logger->warn("Dropped $event_type event due to backpressure");
    return;
  }
  
  # Track queue size
  $self->backpressure->increment_queue();
  
  my $is_transaction = ($event_type eq 'transaction');
  my $is_envelope = $is_transaction || ref($payload) eq 'Sentry::Envelope';
  my $endpoint = $is_envelope ? 'envelope' : 'store';
  my $url = $self->_sentry_url . "/$endpoint/";
  my $tx;

  if ($is_envelope) {
    my $envelope;
    if (ref($payload) eq 'Sentry::Envelope') {
      # Direct envelope object
      $envelope = $payload;
    } else {
      # Create envelope for transaction
      $envelope = Sentry::Envelope->new(
        event_id => $payload->{event_id},
        body     => $payload,
      );
    }
    
    my $serialized = $envelope->serialize;
    $tx = $self->_http->post($url => $self->_headers, $serialized);
  } else {
    $tx = $self->_http->post($url => $self->_headers, json => $payload);
  }

  # Update rate limits from response headers
  if ($tx->res->headers) {
    my %headers = map { lc($_) => $tx->res->headers->header($_) } 
                  $tx->res->headers->names->@*;
    $self->rate_limit->update_from_headers(\%headers);
  }

  # Clean up expired rate limits
  $self->rate_limit->clear_expired();
  
  # Update queue size
  $self->backpressure->decrement_queue();

  logger->log(
    sprintf(
      qq{Sentry request done. Payload: \n<<<<<<<<<<<<<<\n%s\n<<<<<<<<<<<<<<\nCode: %s},
      $tx->req->body, $tx->res->code // 'ERROR'
    ),
    __PACKAGE__
  );

  if (!defined $tx->res->code || $tx->res->is_error) {
    logger->warn('Error: ' . ($tx->res->error // {})->{message});
    return;
  }

  if ($tx->res->code == HTTP_BAD_REQUEST) {
    logger->error($tx->res->body);
  }

  return $tx->res->json;
}

sub send_envelope ($self, $envelope) {
  return $self->send($envelope);
}

1;
