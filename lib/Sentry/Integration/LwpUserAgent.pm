package Sentry::Integration::LwpUserAgent;
use Mojo::Base 'Sentry::Integration::Base', -signatures;

use Mojo::Util qw(dumper);
use Sentry::Util 'around';
use Time::HiRes;

has _package_name => 'LWP::UserAgent';
has breadcrumbs   => 1;
has tracing       => 1;

sub setup_once ($self, $add_global_event_processor, $get_current_hub) {
  return if (!$self->breadcrumbs && !$self->tracing);

  around($self->_package_name, request => sub ($orig, $lwp, $request, @args) {
    my $url = $request->uri;
    
    # Exclude Sentry requests
    return $orig->($lwp, $request, @args) if $request->header('x-sentry-auth');

    my $hub = $get_current_hub->();
    my $span;
    my $start_time = Time::HiRes::time();

    if ($self->tracing && (my $parent_span = $hub->get_scope()->get_span)) {
      $span = $parent_span->start_child({
        op => 'http.client',
        description => $request->method . ' ' . $url->host,
        data => {
          # OpenTelemetry semantic conventions
          'http.request.method' => $request->method,
          'server.address' => $url->host,
          'server.port' => $url->port,
          'url.full' => $url->as_string,
          'url.scheme' => $url->scheme,
          'url.path' => $url->path // '',
          'http.query' => $url->query // '',
          'http.request.header.user_agent' => $request->header('user-agent') // '',
          'http.request.body.size' => length($request->content // ''),
          'thread.id' => $$,
        },
      });

      # Add trace propagation headers
      $request->header('sentry-trace' => $span->to_trace_parent);
    }

    my $result = $orig->($lwp, $request, @args);
    my $duration = Time::HiRes::time() - $start_time;

    # Enhanced breadcrumb
    $hub->add_breadcrumb({
      type => 'http',
      category => 'http.client',
      data => {
        'http.request.method' => $request->method,
        'url.full' => $url->as_string,
        'http.response.status_code' => $result->code,
        'http.response_content_length' => length($result->content // ''),
        'duration_ms' => int($duration * 1000),
        'server.address' => $url->host,
      },
      level => $result->is_success ? 'info' : 
               $result->is_client_error ? 'warning' : 'error',
    }) if $self->breadcrumbs;

    if ($span) {
      # Update span data with response information
      my $data = $span->data || {};
      $data->{'http.response.status_code'} = $result->code;
      $data->{'http.response_content_length'} = length($result->content // '');
      $data->{'duration_ms'} = int($duration * 1000);
      $span->data($data);
      
      $span->set_http_status($result->code);
      $span->finish();
    }

    # Capture failed requests if configured
    if ($result->is_error) {
      $self->_maybe_capture_http_error($request, $result, $duration, $span);
    }

    return $result;
  });
}

# Helper methods for HTTP client telemetry
sub _serialize_baggage ($self, $baggage) {
  # Simple baggage serialization - can be enhanced
  return join(',', map { "$_=" . $baggage->{$_} } keys %$baggage);
}

sub _maybe_capture_http_error ($self, $request, $response, $duration, $span) {
  my $hub = Sentry::Hub->get_current_hub();
  my $client = $hub->client;
  
  # Only capture if configured to do so
  return unless $client && $client->_options->{capture_failed_requests};
  
  # Don't capture 4xx errors by default, only 5xx
  return if $response->is_client_error && !$client->_options->{capture_4xx_errors};
  
  Sentry::SDK->capture_message(
    sprintf('HTTP %s: %s %s', $response->code, $request->method, $request->uri),
    'error',
    {
      contexts => {
        http => {
          method => $request->method,
          url => $request->uri->as_string,
          status_code => $response->code,
          response_size => length($response->content // ''),
          duration_ms => int($duration * 1000),
        }
      },
      tags => {
        http_status_code => $response->code,
        http_method => $request->method,
        http_client => 'lwp',
      }
    }
  );
}

1;
