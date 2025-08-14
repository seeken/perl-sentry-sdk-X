package Sentry::Integration::MojoUserAgent;
use Mojo::Base 'Sentry::Integration::Base', -signatures;

use Mojo::Util qw(dumper);
use Sentry::Util 'around';
use Time::HiRes;

has breadcrumbs => 1;
has tracing     => 1;

sub setup_once ($self, $add_global_event_processor, $get_current_hub) {
  return if (!$self->breadcrumbs && !$self->tracing);

  around('Mojo::UserAgent', start => sub ($orig, $ua, $tx, $cb = undef) {
    my $url = $tx->req->url;

    # Exclude Requests to the Sentry server
    return $orig->($ua, $tx, $cb)
      if $tx->req->headers->header('x-sentry-auth');

    my $hub = $get_current_hub->();
    my $span;
    my $start_time = Time::HiRes::time();

    if ($self->tracing && (my $parent_span = $hub->get_scope()->get_span)) {
      $span = $parent_span->start_child({
        op => 'http.client',
        description => $tx->req->method . ' ' . $url->host,
        data => {
          # OpenTelemetry semantic conventions
          'http.request.method' => $tx->req->method,
          'server.address' => $url->host,
          'server.port' => $url->port,
          'url.full' => $url->to_string,
          'url.scheme' => $url->scheme,
          'url.path' => $url->path,
          'http.query' => $url->query->to_string,
          'http.request.header.user_agent' => $tx->req->headers->user_agent,
          'http.request.body.size' => length($tx->req->body // ''),
          'thread.id' => $$,
        },
      });

      # Add trace propagation headers
      $tx->req->headers->add('sentry-trace' => $span->to_trace_parent);
    }

    my $result = $orig->($ua, $tx, $cb);
    my $duration = Time::HiRes::time() - $start_time;

    # Enhanced breadcrumb
    $hub->add_breadcrumb({
      type => 'http',
      category => 'http.client',
      data => {
        'http.request.method' => $tx->req->method,
        'url.full' => $url->to_string,
        'http.response.status_code' => $tx->res->code,
        'http.response_content_length' => length($tx->res->body // ''),
        'duration_ms' => int($duration * 1000),
        'server.address' => $url->host,
      },
      level => $tx->res->is_success ? 'info' : 
               $tx->res->is_client_error ? 'warning' : 'error',
    }) if $self->breadcrumbs;

    if ($span) {
      # Update span data with response information
      my $data = $span->data || {};
      $data->{'http.response.status_code'} = $tx->res->code;
      $data->{'http.response_content_length'} = length($tx->res->body // '');
      $data->{'duration_ms'} = int($duration * 1000);
      $span->data($data);
      
      if (my $http_status = $tx->res->code) {
        $span->set_http_status($http_status);
      }
      $span->finish();
    }

    # Capture failed requests if configured
    if ($tx->res->is_error) {
      $self->_maybe_capture_http_error($tx, $duration, $span);
    }

    return $result;
  });
}

# Helper methods for HTTP client telemetry
sub _serialize_baggage ($self, $baggage) {
  # Simple baggage serialization - can be enhanced
  return join(',', map { "$_=" . $baggage->{$_} } keys %$baggage);
}

sub _maybe_capture_http_error ($self, $tx, $duration, $span) {
  my $hub = Sentry::Hub->get_current_hub();
  my $client = $hub->client;
  
  # Only capture if configured to do so
  return unless $client && $client->_options->{capture_failed_requests};
  
  # Don't capture 4xx errors by default, only 5xx
  return if $tx->res->is_client_error && !$client->_options->{capture_4xx_errors};
  
  Sentry::SDK->capture_message(
    sprintf('HTTP %s: %s %s', $tx->res->code, $tx->req->method, $tx->req->url),
    'error',
    {
      contexts => {
        http => {
          method => $tx->req->method,
          url => $tx->req->url->to_string,
          status_code => $tx->res->code,
          response_size => length($tx->res->body // ''),
          duration_ms => int($duration * 1000),
        }
      },
      tags => {
        http_status_code => $tx->res->code,
        http_method => $tx->req->method,
        http_client => 'mojo',
      }
    }
  );
}

1;
