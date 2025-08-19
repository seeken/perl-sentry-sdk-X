package Sentry::ErrorHandling::Classification;
use Mojo::Base -base, -signatures;

use List::Util qw(first);

=head1 NAME

Sentry::ErrorHandling::Classification - Advanced error classification and enrichment

=head1 DESCRIPTION

Provides intelligent error classification, severity detection, and automatic
tagging to improve error organization and alerting in Sentry.

=cut

# Classification rules
has classification_rules => sub { [
  'severity_classification',
  'category_classification',
  'business_impact_classification',
  'error_source_classification',
  'recovery_classification'
] };

# Severity patterns
has severity_patterns => sub { {
  fatal => [
    qr/fatal|critical|emergency/i,
    qr/segmentation fault|core dumped/i,
    qr/out of memory|memory exhausted/i,
    qr/database unavailable|connection refused/i,
    qr/payment.*(?:failed|error|timeout)/i,
  ],
  
  error => [
    qr/error|exception|failed/i,
    qr/unauthorized|forbidden|access denied/i,
    qr/timeout|connection.*(?:lost|reset)/i,
    qr/invalid.*(?:request|input|data)/i,
    qr/syntax.*error|parse.*error/i,
  ],
  
  warning => [
    qr/warning|deprecated/i,
    qr/slow.*(?:query|request|response)/i,
    qr/retry|fallback/i,
    qr/cache.*(?:miss|expired)/i,
  ],
  
  info => [
    qr/info|notice|debug/i,
    qr/started|stopped|initialized/i,
  ],
} };

# Category patterns
has category_patterns => sub { {
  database => [
    qr/DBI|DBD|database|sql|mysql|postgresql|sqlite/i,
    qr/connection.*pool|query.*(?:timeout|failed)/i,
  ],
  
  network => [
    qr/HTTP|network|connection|socket|timeout/i,
    qr/LWP|Mojo::UserAgent|curl|wget/i,
    qr/DNS|host.*not.*found/i,
  ],
  
  authentication => [
    qr/auth|login|password|token|session/i,
    qr/unauthorized|forbidden|permission/i,
  ],
  
  validation => [
    qr/validation|invalid|malformed/i,
    qr/schema|constraint|format/i,
  ],
  
  business_logic => [
    qr/business|logic|rule|policy/i,
    qr/insufficient.*(?:funds|credit|quota)/i,
  ],
  
  infrastructure => [
    qr/memory|disk|cpu|load/i,
    qr/service.*unavailable|server.*error/i,
  ],
  
  integration => [
    qr/API|webhook|external|third.*party/i,
    qr/partner|vendor|service.*call/i,
  ],
} };

# Business impact patterns
has business_impact_patterns => sub { {
  high => [
    qr/payment|billing|checkout|order/i,
    qr/security|breach|unauthorized/i,
    qr/data.*(?:loss|corruption)/i,
  ],
  
  medium => [
    qr/user.*(?:registration|profile|account)/i,
    qr/report|export|import/i,
    qr/notification|email|sms/i,
  ],
  
  low => [
    qr/logging|monitoring|analytics/i,
    qr/cache|optimization/i,
    qr/cleanup|maintenance/i,
  ],
} };

=head2 classify_error($exception, $event_data, $options)

Classify an error and enrich event data with classification information.

=cut

sub classify_error ($self, $exception, $event_data, $options = {}) {
  # Initialize classification data
  $event_data->{tags} //= {};
  $event_data->{extra} //= {};
  $event_data->{extra}{classification} //= {};
  
  # Apply classification rules
  for my $rule (@{$self->classification_rules}) {
    my $method = "_apply_$rule";
    if ($self->can($method)) {
      eval {
        $self->$method($exception, $event_data, $options);
      };
      warn "Error in classification rule $rule: $@" if $@;
    }
  }
  
  # Add metadata
  $event_data->{extra}{classification}{classified_at} = time();
  $event_data->{extra}{classification}{classifier_version} = '1.0';
  
  return $event_data;
}

=head2 Classification rule implementations

=cut

sub _apply_severity_classification ($self, $exception, $event_data, $options) {
  my $current_level = $event_data->{level} || 'error';
  
  # Extract error content for analysis
  my $error_text = $self->_extract_error_content($exception, $event_data);
  return unless $error_text;
  
  # Check severity patterns
  my $detected_severity = $self->_detect_severity($error_text, $current_level);
  
  if ($detected_severity && $detected_severity ne $current_level) {
    # Update severity if auto-detected level is more severe
    my %severity_rank = (fatal => 4, error => 3, warning => 2, info => 1);
    
    if ($severity_rank{$detected_severity} > $severity_rank{$current_level}) {
      $event_data->{level} = $detected_severity;
      $event_data->{tags}{severity_adjusted} = 1;
      $event_data->{extra}{classification}{original_level} = $current_level;
      $event_data->{extra}{classification}{detected_level} = $detected_severity;
    }
  }
  
  # Add severity-specific tags
  if ($detected_severity eq 'fatal') {
    $event_data->{tags}{requires_immediate_attention} = 1;
    $event_data->{tags}{escalate} = 1;
  } elsif ($detected_severity eq 'error') {
    $event_data->{tags}{actionable} = 1;
  }
}

sub _apply_category_classification ($self, $exception, $event_data, $options) {
  my $error_text = $self->_extract_error_content($exception, $event_data);
  return unless $error_text;
  
  # Detect error categories
  my @detected_categories = $self->_detect_categories($error_text, $exception, $event_data);
  
  if (@detected_categories) {
    $event_data->{tags}{error_category} = $detected_categories[0];  # Primary category
    $event_data->{extra}{classification}{categories} = \@detected_categories;
    
    # Add category-specific tags
    for my $category (@detected_categories) {
      $event_data->{tags}{"category_$category"} = 1;
      
      # Category-specific logic
      $self->_apply_category_specific_logic($category, $event_data, $exception);
    }
  }
}

sub _apply_business_impact_classification ($self, $exception, $event_data, $options) {
  my $error_text = $self->_extract_error_content($exception, $event_data);
  return unless $error_text;
  
  # Detect business impact
  my $impact_level = $self->_detect_business_impact($error_text, $event_data);
  
  if ($impact_level) {
    $event_data->{tags}{business_impact} = $impact_level;
    $event_data->{extra}{classification}{business_impact} = $impact_level;
    
    # Set priority based on impact
    if ($impact_level eq 'high') {
      $event_data->{tags}{priority} = 'high';
      $event_data->{tags}{escalate} = 1;
    } elsif ($impact_level eq 'medium') {
      $event_data->{tags}{priority} = 'medium';
    } else {
      $event_data->{tags}{priority} = 'low';
    }
  }
}

sub _apply_error_source_classification ($self, $exception, $event_data, $options) {
  # Analyze where the error originated
  my $source_info = $self->_analyze_error_source($exception, $event_data);
  
  if ($source_info) {
    $event_data->{tags}{error_source} = $source_info->{source};
    $event_data->{extra}{classification}{source_details} = $source_info;
    
    # Source-specific tags
    if ($source_info->{source} eq 'external_api') {
      $event_data->{tags}{external_dependency} = 1;
    } elsif ($source_info->{source} eq 'user_input') {
      $event_data->{tags}{input_validation_required} = 1;
    } elsif ($source_info->{source} eq 'configuration') {
      $event_data->{tags}{configuration_issue} = 1;
    }
  }
}

sub _apply_recovery_classification ($self, $exception, $event_data, $options) {
  my $error_text = $self->_extract_error_content($exception, $event_data);
  return unless $error_text;
  
  # Analyze if the error is recoverable
  my $recovery_info = $self->_analyze_recoverability($error_text, $exception, $event_data);
  
  if ($recovery_info) {
    $event_data->{tags}{recoverable} = $recovery_info->{recoverable} ? 1 : 0;
    $event_data->{extra}{classification}{recovery} = $recovery_info;
    
    if ($recovery_info->{recoverable}) {
      $event_data->{tags}{auto_retry} = 1 if $recovery_info->{auto_retry_suggested};
    } else {
      $event_data->{tags}{requires_manual_intervention} = 1;
    }
  }
}

=head2 Detection and analysis methods

=cut

sub _extract_error_content ($self, $exception, $event_data) {
  my @content_parts;
  
  # Error message
  if (my $message = $self->_get_error_message($exception, $event_data)) {
    push @content_parts, $message;
  }
  
  # Exception type
  if (my $type = $self->_get_error_type($exception, $event_data)) {
    push @content_parts, $type;
  }
  
  # Stack trace context
  if (my $frames = $self->_get_stack_frames($exception, $event_data)) {
    for my $frame (splice(@$frames, 0, 3)) {  # Top 3 frames
      if (my $function = $self->_get_frame_function($frame)) {
        push @content_parts, $function;
      }
    }
  }
  
  return join(' ', @content_parts);
}

sub _detect_severity ($self, $error_text, $current_level) {
  my $patterns = $self->severity_patterns;
  
  # Check patterns in order of severity
  for my $level (qw(fatal error warning info)) {
    for my $pattern (@{$patterns->{$level}}) {
      return $level if $error_text =~ /$pattern/;
    }
  }
  
  return $current_level;
}

sub _detect_categories ($self, $error_text, $exception, $event_data) {
  my @categories;
  my $patterns = $self->category_patterns;
  
  for my $category (keys %$patterns) {
    for my $pattern (@{$patterns->{$category}}) {
      if ($error_text =~ /$pattern/) {
        push @categories, $category;
        last;
      }
    }
  }
  
  # Additional context-based detection
  if ($event_data->{contexts}{database}) {
    push @categories, 'database' unless grep { $_ eq 'database' } @categories;
  }
  
  if ($event_data->{contexts}{request}) {
    push @categories, 'network' unless grep { $_ eq 'network' } @categories;
  }
  
  return @categories;
}

sub _detect_business_impact ($self, $error_text, $event_data) {
  my $patterns = $self->business_impact_patterns;
  
  # Check patterns in order of impact
  for my $level (qw(high medium low)) {
    for my $pattern (@{$patterns->{$level}}) {
      return $level if $error_text =~ /$pattern/;
    }
  }
  
  # Context-based impact detection
  if ($event_data->{contexts}{user}{is_premium}) {
    return 'high';
  }
  
  if (my $route = $event_data->{contexts}{route}{name}) {
    return 'high' if $route =~ /payment|checkout|billing/i;
    return 'medium' if $route =~ /user|profile|account/i;
  }
  
  return 'medium';  # Default impact
}

sub _analyze_error_source ($self, $exception, $event_data) {
  # Analyze stack trace for source
  my $frames = $self->_get_stack_frames($exception, $event_data);
  return undef unless $frames && @$frames;
  
  my $top_frame = $frames->[0];
  my $source_file = $self->_get_frame_filename($top_frame);
  
  return undef unless $source_file;
  
  # Classify based on file patterns
  if ($source_file =~ /integration|api|client/i) {
    return {
      source => 'external_api',
      file => $source_file,
      confidence => 0.8,
    };
  }
  
  if ($source_file =~ /validation|input|form/i) {
    return {
      source => 'user_input',
      file => $source_file,
      confidence => 0.9,
    };
  }
  
  if ($source_file =~ /config|settings/i) {
    return {
      source => 'configuration',
      file => $source_file,
      confidence => 0.7,
    };
  }
  
  if ($source_file =~ /model|data|db/i) {
    return {
      source => 'data_layer',
      file => $source_file,
      confidence => 0.6,
    };
  }
  
  return {
    source => 'application_logic',
    file => $source_file,
    confidence => 0.5,
  };
}

sub _analyze_recoverability ($self, $error_text, $exception, $event_data) {
  # Patterns for recoverable errors
  my @recoverable_patterns = (
    qr/timeout|connection.*(?:reset|lost)/i,
    qr/temporary|retry|again/i,
    qr/rate.*limit|quota.*exceeded/i,
    qr/service.*unavailable/i,
  );
  
  # Patterns for non-recoverable errors
  my @non_recoverable_patterns = (
    qr/syntax.*error|parse.*error/i,
    qr/permission.*denied|forbidden/i,
    qr/not.*found|does.*not.*exist/i,
    qr/invalid.*(?:format|data|input)/i,
  );
  
  my $recoverable;
  my $auto_retry_suggested = 0;
  
  # Check non-recoverable patterns first
  for my $pattern (@non_recoverable_patterns) {
    if ($error_text =~ /$pattern/) {
      $recoverable = 0;
      last;
    }
  }
  
  # Check recoverable patterns if not already determined
  if (!defined $recoverable) {
    for my $pattern (@recoverable_patterns) {
      if ($error_text =~ /$pattern/) {
        $recoverable = 1;
        $auto_retry_suggested = 1 if $error_text =~ /timeout|temporary|rate.*limit/i;
        last;
      }
    }
  }
  
  # Default assessment
  $recoverable //= 1;  # Assume recoverable by default
  
  return {
    recoverable => $recoverable,
    auto_retry_suggested => $auto_retry_suggested,
    confidence => defined($recoverable) ? 0.8 : 0.3,
  };
}

sub _apply_category_specific_logic ($self, $category, $event_data, $exception) {
  if ($category eq 'database') {
    # Database-specific enrichment
    $event_data->{tags}{requires_db_analysis} = 1;
    
    if ($event_data->{extra}{classification}{recovery}{recoverable}) {
      $event_data->{tags}{db_connection_retry} = 1;
    }
  }
  
  if ($category eq 'network') {
    # Network-specific enrichment
    $event_data->{tags}{network_dependency} = 1;
    
    if (my $url = $self->_extract_url_from_error($exception, $event_data)) {
      $event_data->{extra}{classification}{target_url} = $url;
    }
  }
  
  if ($category eq 'authentication') {
    # Auth-specific enrichment
    $event_data->{tags}{security_related} = 1;
    $event_data->{tags}{audit_required} = 1;
  }
}

=head2 Helper methods

=cut

sub _get_error_message ($self, $exception, $event_data) {
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

sub _get_error_type ($self, $exception, $event_data) {
  # From exception object
  if (ref $exception) {
    return ref $exception;
  }
  
  # From event data
  if (my $exc_type = $event_data->{exception}{values}[0]{type}) {
    return $exc_type;
  }
  
  return 'Generic';
}

sub _get_stack_frames ($self, $exception, $event_data) {
  # From Mojo::Exception
  if (ref $exception eq 'Mojo::Exception' && $exception->can('frames')) {
    return $exception->frames;
  }
  
  # From event data
  if (my $stacktrace = $event_data->{exception}{values}[0]{stacktrace}) {
    return $stacktrace->{frames} if ref $stacktrace eq 'HASH';
    return $stacktrace->frames if ref $stacktrace && $stacktrace->can('frames');
  }
  
  return undef;
}

sub _get_frame_function ($self, $frame) {
  if (ref $frame eq 'HASH') {
    return $frame->{function} || $frame->{subroutine};
  } elsif (ref $frame eq 'ARRAY') {
    return $frame->[3];  # subroutine
  }
  
  return undef;
}

sub _get_frame_filename ($self, $frame) {
  if (ref $frame eq 'HASH') {
    return $frame->{filename};
  } elsif (ref $frame eq 'ARRAY') {
    return $frame->[1];  # filename
  }
  
  return undef;
}

sub _extract_url_from_error ($self, $exception, $event_data) {
  my $error_text = $self->_extract_error_content($exception, $event_data);
  
  if ($error_text =~ /(https?:\/\/[^\s]+)/i) {
    return $1;
  }
  
  return undef;
}

1;

=head1 EXAMPLES

  # Basic usage
  my $classifier = Sentry::ErrorHandling::Classification->new();
  $classifier->classify_error($exception, $event_data);
  
  # Custom severity patterns
  $classifier->severity_patterns->{critical} = [
    qr/payment.*failed|billing.*error/i,
    @{$classifier->severity_patterns->{critical}},
  ];

=head1 SEE ALSO

L<Sentry::ErrorHandling::Fingerprinting>, L<Sentry::ErrorHandling::Context>, L<Sentry::ErrorHandling::Sampling>

=cut