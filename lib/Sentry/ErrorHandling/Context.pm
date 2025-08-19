package Sentry::ErrorHandling::Context;
use Mojo::Base -base, -signatures;

use Scalar::Util qw(blessed);
use Time::HiRes qw(time);
use Sys::Hostname qw(hostname);
use Cwd;

=head1 NAME

Sentry::ErrorHandling::Context - Enhanced error context collection and enrichment

=head1 DESCRIPTION

Automatically captures rich contextual information for errors, including user data,
environment information, request details, and custom application contexts.

=cut

# Context processors
has processors => sub { [] };

# Default context providers
has default_providers => sub { [
  'user_context',
  'environment_context',
  'request_context', 
  'session_context',
  'performance_context',
  'system_context'
] };

# Context collection configuration
has config => sub { {
  # Maximum context data size in bytes
  max_context_size => 65536,  # 64KB
  
  # Enable automatic PII scrubbing
  scrub_pii => 1,
  
  # PII scrubbing patterns
  pii_patterns => [
    qr/password/i,
    qr/secret/i,
    qr/token/i,
    qr/api[_-]?key/i,
    qr/credit[_-]?card/i,
    qr/ssn|social[_-]?security/i,
  ],
  
  # Context timeout in seconds
  context_timeout => 5,
  
  # Enable context caching
  enable_caching => 1,
  
  # Cache TTL in seconds
  cache_ttl => 300,
} };

# Context cache
has _context_cache => sub { {} };

=head2 enrich_event($event_data, $exception, $options)

Enrich error event with comprehensive contextual information.

=cut

sub enrich_event ($self, $event_data, $exception = undef, $options = {}) {
  # Initialize contexts section
  $event_data->{contexts} //= {};
  
  # Collect contexts from default providers
  for my $provider (@{$self->default_providers}) {
    next if $options->{skip_providers} && grep { $_ eq $provider } @{$options->{skip_providers}};
    
    my $method = "_collect_$provider";
    if ($self->can($method)) {
      eval {
        local $SIG{ALRM} = sub { die "Context collection timeout\n" };
        alarm $self->config->{context_timeout};
        
        my $context = $self->$method($event_data, $exception, $options);
        if ($context && ref $context eq 'HASH') {
          $self->_merge_context($event_data->{contexts}, $provider =~ s/_context$//r, $context);
        }
        
        alarm 0;
      };
      if ($@ && $@ ne "Context collection timeout\n") {
        warn "Error collecting $provider: $@";
      }
    }
  }
  
  # Apply custom processors
  for my $processor (@{$self->processors}) {
    eval {
      $processor->($event_data, $exception, $options);
    };
    warn "Error in custom context processor: $@" if $@;
  }
  
  # Scrub PII if enabled
  if ($self->config->{scrub_pii}) {
    $self->_scrub_pii($event_data);
  }
  
  # Enforce size limits
  $self->_enforce_size_limits($event_data);
  
  return $event_data;
}

=head2 Default context providers

=cut

sub _collect_user_context ($self, $event_data, $exception, $options) {
  my $context = {};
  
  # Try to extract user information from various sources
  if (my $user_id = $self->_extract_user_id($options)) {
    $context->{id} = $user_id;
  }
  
  if (my $username = $self->_extract_username($options)) {
    $context->{username} = $username;
  }
  
  if (my $email = $self->_extract_user_email($options)) {
    $context->{email} = $email;
  }
  
  # Include user agent if available
  if (my $user_agent = $ENV{HTTP_USER_AGENT} || $options->{user_agent}) {
    $context->{user_agent} = $user_agent;
  }
  
  # Include IP address
  if (my $ip = $self->_extract_client_ip($options)) {
    $context->{ip_address} = $ip;
  }
  
  return %$context ? $context : undef;
}

sub _collect_environment_context ($self, $event_data, $exception, $options) {
  return {
    hostname => hostname(),
    pid => $$,
    perl_version => $^V ? $^V->stringify : $],
    os => $^O,
    architecture => $Config::Config{archname} // 'unknown',
    timezone => $ENV{TZ} // 'unknown',
    working_directory => Cwd::getcwd(),
    environment => $ENV{PLACK_ENV} || $ENV{MOJO_MODE} || $ENV{PERL_ENV} || 'production',
  };
}

sub _collect_request_context ($self, $event_data, $exception, $options) {
  my $context = {};
  
  # HTTP request information
  if (my $method = $ENV{REQUEST_METHOD} || $options->{request_method}) {
    $context->{method} = $method;
  }
  
  if (my $uri = $ENV{REQUEST_URI} || $options->{request_uri}) {
    $context->{url} = $uri;
  }
  
  if (my $query = $ENV{QUERY_STRING} || $options->{query_string}) {
    $context->{query_string} = $query;
  }
  
  # Headers (sanitized)
  if (my $headers = $self->_extract_request_headers($options)) {
    $context->{headers} = $headers;
  }
  
  # Request body (if small and not binary)
  if (my $body = $self->_extract_request_body($options)) {
    $context->{body} = $body;
  }
  
  # Request size
  if (my $length = $ENV{CONTENT_LENGTH} || $options->{content_length}) {
    $context->{body_size} = int($length);
  }
  
  return %$context ? $context : undef;
}

sub _collect_session_context ($self, $event_data, $exception, $options) {
  my $context = {};
  
  # Session ID if available
  if (my $session_id = $self->_extract_session_id($options)) {
    $context->{session_id} = $session_id;
  }
  
  # Session data (sanitized)
  if (my $session_data = $self->_extract_session_data($options)) {
    $context->{data} = $session_data;
  }
  
  # Session metadata
  if (my $session_start = $options->{session_start_time}) {
    $context->{started_at} = $session_start;
    $context->{duration} = time() - $session_start;
  }
  
  return %$context ? $context : undef;
}

sub _collect_performance_context ($self, $event_data, $exception, $options) {
  my $context = {};
  
  # Memory usage
  if (open my $fh, '<', '/proc/self/status') {
    while (defined(my $line = <$fh>)) {
      if ($line =~ /^VmRSS:\s+(\d+)\s+kB/) {
        $context->{memory_usage} = int($1) * 1024;  # Convert to bytes
        last;
      }
    }
    close $fh;
  }
  
  # Request timing if available
  if (my $start_time = $options->{request_start_time}) {
    $context->{request_duration} = time() - $start_time;
  }
  
  # Load averages (Linux)
  if (open my $fh, '<', '/proc/loadavg') {
    if (defined(my $line = <$fh>)) {
      my ($load1, $load5, $load15) = split /\s+/, $line;
      $context->{load_average} = {
        '1min' => $load1 + 0,
        '5min' => $load5 + 0, 
        '15min' => $load15 + 0,
      };
    }
    close $fh;
  }
  
  # Database connection info if available
  if (my $db_stats = $options->{database_stats}) {
    $context->{database} = $db_stats;
  }
  
  return %$context ? $context : undef;
}

sub _collect_system_context ($self, $event_data, $exception, $options) {
  my $context = {};
  
  # Disk usage for current directory
  if (my $df_output = `df -h . 2>/dev/null | tail -1`) {
    if ($df_output =~ /\s+(\d+%)\s+/) {
      $context->{disk_usage} = $1;
    }
  }
  
  # System uptime
  if (open my $fh, '<', '/proc/uptime') {
    if (defined(my $line = <$fh>)) {
      my ($uptime) = split /\s+/, $line;
      $context->{system_uptime} = int($uptime);
    }
    close $fh;
  }
  
  # Number of processes
  if (opendir my $dh, '/proc') {
    my $proc_count = grep { /^\d+$/ } readdir($dh);
    $context->{process_count} = $proc_count;
    closedir $dh;
  }
  
  return %$context ? $context : undef;
}

=head2 Helper methods for context extraction

=cut

sub _extract_user_id ($self, $options) {
  return $options->{user_id} 
      || $ENV{USER_ID}
      || $ENV{LOGNAME}
      || $ENV{USER};
}

sub _extract_username ($self, $options) {
  return $options->{username}
      || $ENV{USERNAME}
      || $ENV{LOGNAME}
      || $ENV{USER};
}

sub _extract_user_email ($self, $options) {
  return $options->{user_email}
      || $ENV{USER_EMAIL};
}

sub _extract_client_ip ($self, $options) {
  return $options->{client_ip}
      || $ENV{HTTP_X_FORWARDED_FOR}
      || $ENV{HTTP_X_REAL_IP}
      || $ENV{REMOTE_ADDR};
}

sub _extract_session_id ($self, $options) {
  return $options->{session_id}
      || $ENV{SESSION_ID};
}

sub _extract_session_data ($self, $options) {
  my $data = $options->{session_data} || {};
  
  # Remove sensitive keys
  my %sanitized = %$data;
  for my $key (keys %sanitized) {
    if ($self->_is_sensitive_key($key)) {
      $sanitized{$key} = '[SCRUBBED]';
    }
  }
  
  return %sanitized ? \%sanitized : undef;
}

sub _extract_request_headers ($self, $options) {
  my $headers = $options->{headers} || {};
  my %sanitized;
  
  # Include common non-sensitive headers
  for my $key (keys %$headers) {
    my $lower_key = lc($key);
    next if $lower_key =~ /authorization|cookie|password|secret|token/;
    
    $sanitized{$key} = $headers->{$key};
  }
  
  # Also check environment for HTTP headers
  for my $env_key (keys %ENV) {
    next unless $env_key =~ /^HTTP_(.+)$/;
    my $header_name = lc($1);
    $header_name =~ s/_/-/g;
    
    next if $header_name =~ /authorization|cookie|password|secret|token/;
    $sanitized{$header_name} = $ENV{$env_key};
  }
  
  return %sanitized ? \%sanitized : undef;
}

sub _extract_request_body ($self, $options) {
  my $body = $options->{request_body};
  return undef unless defined $body;
  
  # Skip if too large
  return undef if length($body) > 8192;
  
  # Skip if binary
  return undef if $body =~ /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/;
  
  return $body;
}

sub _merge_context ($self, $contexts, $section, $data) {
  $contexts->{$section} //= {};
  
  if (ref $data eq 'HASH') {
    %{$contexts->{$section}} = (%{$contexts->{$section}}, %$data);
  }
}

sub _scrub_pii ($self, $event_data) {
  $self->_scrub_hash($event_data, $self->config->{pii_patterns});
}

sub _scrub_hash ($self, $data, $patterns) {
  return unless ref $data eq 'HASH';
  
  for my $key (keys %$data) {
    if ($self->_is_sensitive_key($key, $patterns)) {
      $data->{$key} = '[SCRUBBED]';
    } elsif (ref $data->{$key} eq 'HASH') {
      $self->_scrub_hash($data->{$key}, $patterns);
    } elsif (ref $data->{$key} eq 'ARRAY') {
      $self->_scrub_array($data->{$key}, $patterns);
    }
  }
}

sub _scrub_array ($self, $data, $patterns) {
  return unless ref $data eq 'ARRAY';
  
  for my $item (@$data) {
    if (ref $item eq 'HASH') {
      $self->_scrub_hash($item, $patterns);
    } elsif (ref $item eq 'ARRAY') {
      $self->_scrub_array($item, $patterns);
    }
  }
}

sub _is_sensitive_key ($self, $key, $patterns = undef) {
  $patterns //= $self->config->{pii_patterns};
  
  for my $pattern (@$patterns) {
    return 1 if $key =~ /$pattern/;
  }
  
  return 0;
}

sub _enforce_size_limits ($self, $event_data) {
  my $max_size = $self->config->{max_context_size};
  return unless $max_size;
  
  # Rough size estimation
  use JSON::XS;
  my $json = JSON::XS->new->utf8;
  
  my $current_size = length($json->encode($event_data->{contexts} || {}));
  
  if ($current_size > $max_size) {
    # Progressively remove less important context sections
    my @sections_to_trim = qw(system performance session request environment user);
    
    for my $section (@sections_to_trim) {
      delete $event_data->{contexts}{$section};
      $current_size = length($json->encode($event_data->{contexts} || {}));
      last if $current_size <= $max_size;
    }
  }
}

=head2 add_processor($processor_sub)

Add a custom context processor.

The processor subroutine receives ($event_data, $exception, $options).

=cut

sub add_processor ($self, $processor_sub) {
  push @{$self->processors}, $processor_sub;
  return $self;
}

1;

=head1 EXAMPLES

  # Basic usage
  my $context = Sentry::ErrorHandling::Context->new();
  $context->enrich_event($event_data, $exception, {
    user_id => 12345,
    session_id => 'sess_abc123',
    request_start_time => $start_time,
  });
  
  # Custom context processor
  $context->add_processor(sub {
    my ($event_data, $exception, $options) = @_;
    
    # Add application-specific context
    $event_data->{contexts}{application} = {
      version => '1.2.3',
      deployment => 'production',
      feature_flags => get_active_feature_flags(),
    };
  });

=head1 SEE ALSO

L<Sentry::ErrorHandling::Fingerprinting>, L<Sentry::ErrorHandling::Sampling>

=cut