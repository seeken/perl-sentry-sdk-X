package Sentry::Tracing::Propagation;
use Mojo::Base -base, -signatures;

use Carp qw(croak);

=head1 NAME

Sentry::Tracing::Propagation - Distributed tracing header propagation

=head1 SYNOPSIS

  use Sentry::Tracing::Propagation;

  # Extract trace context from incoming HTTP headers
  my $context = Sentry::Tracing::Propagation->extract_trace_context({
      'sentry-trace' => $headers->{'sentry-trace'},
      'baggage' => $headers->{'baggage'},
  });

  # Inject trace context into outgoing HTTP headers
  my $span = Sentry::SDK->get_current_span();
  my $headers = {};
  Sentry::Tracing::Propagation->inject_trace_context($span, $headers);

=head1 DESCRIPTION

This module handles distributed tracing header propagation for Sentry, implementing
the sentry-trace and baggage headers according to the W3C Trace Context specification
and Sentry's distributed tracing protocol.

=head1 METHODS

=head2 extract_trace_context

  my $context = Sentry::Tracing::Propagation->extract_trace_context($headers);

Extracts trace context from HTTP headers. Returns a hashref with:

  {
      trace_id => '12345...',        # 32-character hex string
      parent_span_id => '67890...',  # 16-character hex string
      sampled => 1,                  # 1, 0, or undef
      baggage => { ... },            # Dynamic sampling context
  }

=cut

sub extract_trace_context ($class, $headers) {
    my %context;
    
    # Extract sentry-trace header: trace_id-span_id-sampled
    if (my $sentry_trace = $headers->{'sentry-trace'}) {
        %context = $class->_parse_sentry_trace($sentry_trace);
    }
    
    # Extract baggage header for dynamic sampling context
    if (my $baggage = $headers->{'baggage'}) {
        $context{baggage} = $class->_parse_baggage($baggage);
    }
    
    return \%context;
}

=head2 inject_trace_context

  Sentry::Tracing::Propagation->inject_trace_context($span, $headers);

Injects trace context into HTTP headers hashref. Adds:
- sentry-trace: Contains trace_id, span_id, and sampling decision
- baggage: Contains dynamic sampling context and metadata

=cut

sub inject_trace_context ($class, $span_or_context, $headers) {
    return unless $span_or_context;
    
    my $sentry_trace;
    my $baggage;
    
    if (ref $span_or_context eq 'HASH') {
        # Called with trace context hash
        my $context = $span_or_context;
        $sentry_trace = $context->{'sentry-trace'};
        $baggage = $context->{'baggage'};
    } else {
        # Called with span object
        my $span = $span_or_context;
        $sentry_trace = $span->to_trace_parent();
        if (my $span_baggage = $span->get_baggage()) {
            $baggage = $class->_serialize_baggage($span_baggage);
        }
    }
    
    # Add headers if they exist
    $headers->{'sentry-trace'} = $sentry_trace if $sentry_trace;
    $headers->{'baggage'} = $baggage if $baggage;
    
    return $headers;
}

=head2 should_propagate_trace

  my $should = Sentry::Tracing::Propagation->should_propagate_trace($url);

Determines if trace headers should be added to a request based on configured
trace propagation targets.

=cut

sub should_propagate_trace ($class, $url) {
    return 0 unless $url;
    
    require Sentry::Hub;
    my $hub = Sentry::Hub->get_current_hub();
    return 0 unless $hub;
    
    my $client = $hub->client;
    return 0 unless $client;
    
    my $targets = $client->_options->{trace_propagation_targets} || [];
    return 1 unless @$targets;  # If no targets specified, propagate to all
    
    for my $target (@$targets) {
        if (ref($target) eq 'Regexp') {
            return 1 if $url =~ $target;
        } elsif (!ref($target)) {
            return 1 if index($url, $target) == 0;  # Starts with target
        }
    }
    
    return 0;
}

# Private methods

=head2 _parse_sentry_trace

Parse sentry-trace header format: trace_id-span_id-sampled

=cut

sub _parse_sentry_trace ($class, $header) {
    return {} unless $header;
    
    my @parts = split /-/, $header, 3;
    return {} unless @parts >= 2;
    
    my ($trace_id, $span_id, $sampled) = @parts;
    
    # Validate trace_id (32 hex chars) and span_id (16 hex chars)
    return {} unless $trace_id =~ /^[0-9a-f]{32}$/i;
    return {} unless $span_id =~ /^[0-9a-f]{16}$/i;
    
    my %context = (
        trace_id => lc($trace_id),
        parent_span_id => lc($span_id),
    );
    
    # Parse sampling decision
    if (defined $sampled) {
        if ($sampled eq '1') {
            $context{sampled} = 1;
        } elsif ($sampled eq '0') {
            $context{sampled} = 0;
        }
        # Leave undefined for unknown sampling decision
    }
    
    return %context;
}

=head2 _parse_baggage

Parse baggage header according to W3C specification.
Format: key1=value1,key2=value2;metadata,key3=value3

=cut

sub _parse_baggage ($class, $baggage_header) {
    return {} unless $baggage_header;
    
    my %baggage;
    
    # Split on commas, handling quoted values
    for my $item (split /,\s*/, $baggage_header) {
        # Split on first equals sign
        my ($key, $value_with_metadata) = split /=/, $item, 2;
        next unless defined $key && defined $value_with_metadata;
        
        # Extract value before any semicolon (metadata)
        my ($value) = split /;/, $value_with_metadata, 2;
        
        # URL decode if needed
        $key =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
        $value =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg if defined $value;
        
        $baggage{$key} = $value // '';
    }
    
    return \%baggage;
}

=head2 _serialize_baggage

Serialize baggage hash to header format.

=cut

sub _serialize_baggage ($class, $baggage) {
    return '' unless $baggage && %$baggage;
    
    my @items;
    for my $key (sort keys %$baggage) {
        my $value = $baggage->{$key} // '';
        
        # URL encode if needed
        $key =~ s/([^A-Za-z0-9._~-])/sprintf("%%%02X", ord($1))/eg;
        $value =~ s/([^A-Za-z0-9._~-])/sprintf("%%%02X", ord($1))/eg;
        
        push @items, "$key=$value";
    }
    
    return join(', ', @items);
}

=head2 _generate_trace_id

Generate a new 32-character hex trace ID.

=cut

sub _generate_trace_id ($class) {
    return sprintf('%032x', int(rand(2**128)));
}

=head2 _generate_span_id

Generate a new 16-character hex span ID.

=cut

sub _generate_span_id ($class) {
    return sprintf('%016x', int(rand(2**64)));
}

1;

__END__

=head1 DISTRIBUTED TRACING FLOW

=head2 Frontend to Backend

1. Frontend JavaScript SDK creates transaction with trace_id and span_id
2. Frontend makes HTTP request with sentry-trace and baggage headers
3. Backend Perl SDK extracts headers and continues the trace
4. Backend creates child spans for database queries, external APIs, etc.
5. All spans share the same trace_id for correlation

=head2 Backend to External Services

1. Backend creates child span for external API call
2. HTTP client integration injects sentry-trace and baggage headers
3. External service (if Sentry-enabled) continues the trace
4. All operations appear in the same distributed trace

=head2 Headers Format

=head3 sentry-trace

Format: {trace_id}-{span_id}-{sampled}
Example: 12345678901234567890123456789012-1234567890123456-1

=head3 baggage

Format: key1=value1,key2=value2
Sentry-specific keys:
- sentry-public_key: DSN public key
- sentry-trace_id: Same as trace_id in sentry-trace header
- sentry-release: Release identifier
- sentry-environment: Environment name

=head1 CONFIGURATION

Configure trace propagation targets in SDK initialization:

  Sentry::SDK->init({
      trace_propagation_targets => [
          'https://api.example.com',        # Exact URL prefix
          'https://internal-service.local', # Another prefix
          qr/^https:\/\/.*\.mycompany\.com/, # Regex pattern
      ],
  });

If no targets are specified, headers are added to all outgoing requests.

=head1 AUTHOR

Perl Sentry SDK Team

=head1 COPYRIGHT

Copyright 2025- Perl Sentry SDK Team

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut