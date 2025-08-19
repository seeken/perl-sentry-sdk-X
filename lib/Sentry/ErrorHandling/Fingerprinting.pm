package Sentry::ErrorHandling::Fingerprinting;
use Mojo::Base -base, -signatures;

use Digest::SHA qw(sha256_hex);
use List::Util qw(first);

=head1 NAME

Sentry::ErrorHandling::Fingerprinting - Advanced error fingerprinting and grouping

=head1 DESCRIPTION

Provides intelligent error fingerprinting algorithms to group similar errors
together in Sentry, reducing noise and improving issue management.

=cut

# Error fingerprinting strategies
has strategies => sub { [
  'stack_trace_based',
  'error_message_based', 
  'exception_type_based',
  'context_based',
  'custom_rules_based'
] };

# Custom fingerprinting rules
has custom_rules => sub { [] };

# Error grouping configuration
has grouping_config => sub { {
  # Stack trace similarity threshold (0-1)
  stack_similarity_threshold => 0.8,
  
  # Message similarity threshold (0-1) 
  message_similarity_threshold => 0.7,
  
  # Maximum fingerprint components
  max_fingerprint_components => 5,
  
  # Enable fuzzy matching for error messages
  fuzzy_message_matching => 1,
  
  # Ignore dynamic parts in stack traces
  ignore_dynamic_frames => 1,
} };

=head2 generate_fingerprint($exception, $event_data)

Generate a fingerprint for error grouping based on multiple strategies.

=cut

sub generate_fingerprint ($self, $exception, $event_data = {}) {
  my @fingerprint_components;
  
  # Strategy 1: Stack trace based fingerprinting
  if (my $stack_fingerprint = $self->_fingerprint_from_stack_trace($exception, $event_data)) {
    push @fingerprint_components, "stack:$stack_fingerprint";
  }
  
  # Strategy 2: Error message based fingerprinting  
  if (my $message_fingerprint = $self->_fingerprint_from_message($exception, $event_data)) {
    push @fingerprint_components, "message:$message_fingerprint";
  }
  
  # Strategy 3: Exception type based fingerprinting
  if (my $type_fingerprint = $self->_fingerprint_from_exception_type($exception, $event_data)) {
    push @fingerprint_components, "type:$type_fingerprint";
  }
  
  # Strategy 4: Context based fingerprinting
  if (my $context_fingerprint = $self->_fingerprint_from_context($exception, $event_data)) {
    push @fingerprint_components, "context:$context_fingerprint";
  }
  
  # Strategy 5: Custom rules based fingerprinting
  if (my $custom_fingerprint = $self->_fingerprint_from_custom_rules($exception, $event_data)) {
    push @fingerprint_components, "custom:$custom_fingerprint";
  }
  
  # Limit fingerprint components and generate final fingerprint
  my $max_components = $self->grouping_config->{max_fingerprint_components};
  @fingerprint_components = splice(@fingerprint_components, 0, $max_components);
  
  if (@fingerprint_components) {
    my $combined = join('|', @fingerprint_components);
    return sha256_hex($combined);
  }
  
  # Fallback: use default Sentry fingerprinting
  return undef;
}

=head2 _fingerprint_from_stack_trace($exception, $event_data)

Generate fingerprint from stack trace analysis.

=cut

sub _fingerprint_from_stack_trace ($self, $exception, $event_data) {
  my $frames = $self->_extract_stack_frames($exception, $event_data);
  return undef unless $frames && @$frames;
  
  my @significant_frames;
  my $config = $self->grouping_config;
  
  for my $frame (@$frames) {
    # Skip dynamic/generated frames if configured
    next if $config->{ignore_dynamic_frames} && $self->_is_dynamic_frame($frame);
    
    # Extract significant parts of the frame
    my $frame_signature = $self->_normalize_frame_signature($frame);
    push @significant_frames, $frame_signature if $frame_signature;
    
    # Limit to most relevant frames (top of stack)
    last if @significant_frames >= 10;
  }
  
  return undef unless @significant_frames;
  
  # Create fingerprint from top frames
  my $stack_signature = join('::', @significant_frames);
  return sha256_hex($stack_signature);
}

=head2 _fingerprint_from_message($exception, $event_data)

Generate fingerprint from error message analysis.

=cut

sub _fingerprint_from_message ($self, $exception, $event_data) {
  my $message = $self->_extract_error_message($exception, $event_data);
  return undef unless $message;
  
  # Normalize the message for fingerprinting
  my $normalized = $self->_normalize_error_message($message);
  return undef unless $normalized;
  
  return sha256_hex($normalized);
}

=head2 _fingerprint_from_exception_type($exception, $event_data)

Generate fingerprint based on exception type and classification.

=cut

sub _fingerprint_from_exception_type ($self, $exception, $event_data) {
  my $type = $self->_extract_exception_type($exception, $event_data);
  return undef unless $type;
  
  # Include module/class information if available
  if (my $module = $self->_extract_exception_module($exception, $event_data)) {
    return sha256_hex("$module::$type");
  }
  
  return sha256_hex($type);
}

=head2 _fingerprint_from_context($exception, $event_data)

Generate fingerprint from contextual information.

=cut

sub _fingerprint_from_context ($self, $exception, $event_data) {
  my @context_parts;
  
  # Include route/endpoint if it's a web request
  if (my $route = $event_data->{contexts}{route}{name}) {
    push @context_parts, "route:$route";
  }
  
  # Include database operation if it's a DB error
  if (my $db_op = $event_data->{contexts}{database}{operation}) {
    push @context_parts, "db_op:$db_op";
  }
  
  # Include HTTP method and status if available
  if (my $method = $event_data->{request}{method}) {
    push @context_parts, "method:$method";
  }
  
  return undef unless @context_parts;
  
  my $context_signature = join('|', @context_parts);
  return sha256_hex($context_signature);
}

=head2 _fingerprint_from_custom_rules($exception, $event_data)

Apply custom fingerprinting rules defined by the user.

=cut

sub _fingerprint_from_custom_rules ($self, $exception, $event_data) {
  return undef unless @{$self->custom_rules};
  
  for my $rule (@{$self->custom_rules}) {
    if (my $fingerprint = $rule->($exception, $event_data, $self)) {
      return $fingerprint;
    }
  }
  
  return undef;
}

=head2 Helper methods for frame and message analysis

=cut

sub _extract_stack_frames ($self, $exception, $event_data) {
  # Extract from Mojo::Exception
  if (ref $exception eq 'Mojo::Exception' && $exception->can('frames')) {
    return $exception->frames;
  }
  
  # Extract from event data stacktrace
  if (my $stacktrace = $event_data->{exception}{values}[0]{stacktrace}) {
    return $stacktrace->{frames} if ref $stacktrace eq 'HASH';
    return $stacktrace->frames if ref $stacktrace && $stacktrace->can('frames');
  }
  
  return undef;
}

sub _is_dynamic_frame ($self, $frame) {
  my $filename = ref $frame eq 'ARRAY' ? $frame->[1] : $frame->{filename};
  return 0 unless $filename;
  
  # Skip eval, anonymous subs, and generated code
  return 1 if $filename =~ /\(eval \d+\)$/;
  return 1 if $filename =~ /^__ANON__/;
  return 1 if $filename =~ /CodeGenerator/i;
  
  return 0;
}

sub _normalize_frame_signature ($self, $frame) {
  my ($package, $filename, $line, $subroutine);
  
  if (ref $frame eq 'ARRAY') {
    ($package, $filename, $line, $subroutine) = @$frame;
  } elsif (ref $frame eq 'HASH') {
    $package = $frame->{package} // $frame->{module};
    $filename = $frame->{filename};
    $line = $frame->{lineno};
    $subroutine = $frame->{function} // $frame->{subroutine};
  } else {
    return undef;
  }
  
  # Normalize paths (remove absolute paths, focus on relative structure)
  if ($filename) {
    $filename =~ s{^.*/}{};  # Remove directory path
    $filename =~ s{\.p[lm]$}{};  # Remove .pl/.pm extension
  }
  
  # Create signature focusing on logical location
  if ($package && $subroutine) {
    return "$package\::$subroutine";
  } elsif ($filename && $subroutine) {
    return "$filename\::$subroutine";
  } elsif ($package) {
    return $package;
  } elsif ($filename) {
    return $filename;
  }
  
  return undef;
}

sub _extract_error_message ($self, $exception, $event_data) {
  # From exception object
  if (ref $exception && $exception->can('message')) {
    return $exception->message;
  }
  
  # From string
  if (!ref $exception) {
    return $exception;
  }
  
  # From event data
  if (my $message = $event_data->{message}) {
    return ref $message eq 'HASH' ? $message->{formatted} : $message;
  }
  
  if (my $exc_value = $event_data->{exception}{values}[0]{value}) {
    return $exc_value;
  }
  
  return undef;
}

sub _normalize_error_message ($self, $message) {
  return undef unless $message;
  
  # Remove file paths and line numbers
  $message =~ s{/[^\s]+\.p[lm]}{FILE}g;
  $message =~ s{\s+at\s+\S+\s+line\s+\d+}{}g;
  
  # Remove variable content (numbers, IDs, timestamps)
  $message =~ s{\b\d{10,}\b}{TIMESTAMP}g;  # Unix timestamps
  $message =~ s{\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b}{UUID}gi;  # UUIDs
  $message =~ s{\b\d+\b}{NUM}g;  # Other numbers
  
  # Remove memory addresses
  $message =~ s{\b0x[0-9a-f]+\b}{ADDR}gi;
  
  # Remove quotes content but keep structure
  $message =~ s{(['"])[^'"]*\1}{$1CONTENT$1}g;
  
  # Normalize whitespace
  $message =~ s{\s+}{ }g;
  $message =~ s{^\s+|\s+$}{}g;
  
  return length($message) > 10 ? $message : undef;
}

sub _extract_exception_type ($self, $exception, $event_data) {
  # From exception object
  if (ref $exception) {
    return ref $exception;
  }
  
  # From event data
  if (my $exc_type = $event_data->{exception}{values}[0]{type}) {
    return $exc_type;
  }
  
  return undef;
}

sub _extract_exception_module ($self, $exception, $event_data) {
  # From exception object
  if (ref $exception) {
    my $class = ref $exception;
    if ($class =~ /^(.+)::[^:]+$/) {
      return $1;
    }
  }
  
  # From event data
  if (my $module = $event_data->{exception}{values}[0]{module}) {
    return $module;
  }
  
  return undef;
}

=head2 add_custom_rule($rule_sub)

Add a custom fingerprinting rule.

The rule subroutine receives ($exception, $event_data, $fingerprinter) and should
return a fingerprint string or undef.

=cut

sub add_custom_rule ($self, $rule_sub) {
  push @{$self->custom_rules}, $rule_sub;
  return $self;
}

1;

=head1 EXAMPLES

  # Basic usage
  my $fingerprinter = Sentry::ErrorHandling::Fingerprinting->new();
  my $fingerprint = $fingerprinter->generate_fingerprint($exception, $event_data);
  
  # Custom rule for database errors
  $fingerprinter->add_custom_rule(sub {
    my ($exception, $event_data, $fp) = @_;
    if ($event_data->{contexts}{database}) {
      my $operation = $event_data->{contexts}{database}{operation} || 'unknown';
      my $table = $event_data->{contexts}{database}{'db.collection.name'} || 'unknown';
      return sha256_hex("db_error:${operation}:${table}");
    }
    return undef;
  });

=head1 SEE ALSO

L<Sentry::ErrorHandling::Context>, L<Sentry::ErrorHandling::Sampling>

=cut