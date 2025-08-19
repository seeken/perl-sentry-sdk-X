package Sentry::Instrumentation::Spans;
use Mojo::Base -base, -signatures;

use Sentry::Hub;
use Sentry::Tracing::Span;
use Sentry::Tracing::Transaction;
use Time::HiRes qw(time);
use Carp qw(croak);

=head1 NAME

Sentry::Instrumentation::Spans - Custom span creation and management

=head1 SYNOPSIS

  use Sentry::Instrumentation::Spans;
  
  my $spans = Sentry::Instrumentation::Spans->new();
  
  # Create custom transactions
  my $transaction = $spans->start_transaction('background.job', 'Process user data');
  
  # Create custom spans
  my $span = $spans->start_span('db.query', 'SELECT users');
  $span->set_tag('table', 'users');
  $span->set_data('query', 'SELECT * FROM users WHERE active = 1');
  $span->finish();
  
  # Automatic span management
  my $result = $spans->trace('api.request', sub {
    # Your code here
    return $some_result;
  }, {
    op => 'http.request',
    description => 'POST /api/users',
    tags => { method => 'POST', endpoint => '/api/users' }
  });
  
  # Custom span attributes
  $spans->start_span('custom.operation')
        ->set_tag('component', 'auth')
        ->set_data('user_id', 'user123')
        ->add_breadcrumb('Starting authentication')
        ->finish();

=head1 DESCRIPTION

This module provides enhanced span creation and management capabilities for
custom application instrumentation, extending the existing Sentry tracing
infrastructure with application-specific features.

=cut

has 'enabled' => 1;
has 'default_tags' => sub { {} };
has 'default_data' => sub { {} };
has 'auto_finish' => 1;
has '_active_spans' => sub { [] };

=head1 METHODS

=head2 new(%options)

Create a new custom spans manager.

  my $spans = Sentry::Instrumentation::Spans->new(
    enabled => 1,
    default_tags => { service => 'api', version => '1.0' },
    auto_finish => 1
  );

=cut

=head2 Transaction Management

=head3 start_transaction($name, $description = undef, $options = {})

Start a new transaction for application-specific operations.

  my $transaction = $spans->start_transaction(
    'background.job', 
    'Process user notifications',
    { 
      tags => { job_type => 'notification' },
      data => { batch_size => 100 }
    }
  );

=cut

sub start_transaction ($self, $name, $description = undef, $options = {}) {
  return undef unless $self->enabled;
  
  my $hub = Sentry::Hub->get_current_hub();
  
  my $transaction = Sentry::Tracing::Transaction->new({
    name => $name,
    op => $options->{op} // 'custom.transaction',
    description => $description,
    data => { %{$self->default_data}, %{$options->{data} || {}} },
    tags => { %{$self->default_tags}, %{$options->{tags} || {}} },
    start_timestamp => time(),
  });
  
  # Set transaction on current scope
  $hub->get_scope()->set_span($transaction);
  
  return $transaction;
}

=head2 Span Management

=head3 start_span($op, $description = undef, $options = {})

Start a new custom span.

  my $span = $spans->start_span('cache.get', 'Get user profile', {
    tags => { cache_type => 'redis', key => 'user:123' },
    data => { ttl => 3600 }
  });

=cut

sub start_span ($self, $op, $description = undef, $options = {}) {
  return undef unless $self->enabled;
  
  my $hub = Sentry::Hub->get_current_hub();
  my $parent_span = $hub->get_scope()->get_span();
  
  my $span;
  if ($parent_span) {
    $span = $parent_span->start_child({
      op => $op,
      description => $description,
      data => { %{$self->default_data}, %{$options->{data} || {}} },
    });
  } else {
    # Create standalone span (will become transaction)
    $span = Sentry::Tracing::Span->new({
      op => $op,
      description => $description,
      data => { %{$self->default_data}, %{$options->{data} || {}} },
      start_timestamp => time(),
    });
  }
  
  # Apply default and custom tags
  my $all_tags = { %{$self->default_tags}, %{$options->{tags} || {}} };
  for my $key (keys %$all_tags) {
    $span->set_tag($key, $all_tags->{$key});
  }
  
  # Track active spans for auto-cleanup
  push @{$self->_active_spans}, $span if $self->auto_finish;
  
  # Set span on current scope
  $hub->get_scope()->set_span($span);
  
  return Sentry::Instrumentation::Spans::CustomSpan->new(
    span => $span,
    manager => $self
  );
}

=head3 trace($name, $code, $options = {})

Trace a code block with automatic span management.

  my $result = $spans->trace('db.transaction', sub {
    # Database operations
    return $result;
  }, {
    op => 'db.transaction',
    tags => { database => 'users' }
  });

=cut

sub trace ($self, $name, $code, $options = {}) {
  return $code->() unless $self->enabled;
  
  my $span = $self->start_span(
    $options->{op} || $name,
    $options->{description} || $name,
    $options
  );
  
  my $result = eval {
    my $ret = $code->();
    $span->set_status('ok');
    return $ret;
  };
  
  if (my $error = $@) {
    $span->set_status('internal_error');
    $span->set_tag('error', 1);
    $span->set_data('error.message', "$error");
    $span->finish();
    croak $error;
  }
  
  $span->finish();
  return $result;
}

=head3 measure_timing($name, $code, $options = {})

Measure timing of a code block and create span with duration data.

  my $result = $spans->measure_timing('expensive.operation', sub {
    # Expensive operation
  }, { tags => { complexity => 'high' } });

=cut

sub measure_timing ($self, $name, $code, $options = {}) {
  my $start_time = time();
  
  my $result = $self->trace($name, $code, {
    %$options,
    op => $options->{op} || 'performance.timing'
  });
  
  my $duration = time() - $start_time;
  
  # The span is already finished by trace(), but we can add timing to current scope
  my $hub = Sentry::Hub->get_current_hub();
  $hub->add_breadcrumb({
    type => 'default',
    category => 'performance',
    message => "Timed operation: $name",
    level => 'info',
    data => {
      operation => $name,
      duration_ms => int($duration * 1000),
      duration_seconds => $duration
    }
  });
  
  return $result;
}

=head2 Context Management

=head3 with_span_context($span, $code)

Execute code with a specific span as the active context.

  $spans->with_span_context($my_span, sub {
    # Code executed with $my_span as active
  });

=cut

sub with_span_context ($self, $span, $code) {
  my $hub = Sentry::Hub->get_current_hub();
  
  # Save current span
  my $previous_span = $hub->get_scope()->get_span();
  
  # Set new span context
  $hub->get_scope()->set_span($span->can('span') ? $span->span : $span);
  
  my $result = eval { $code->() };
  my $error = $@;
  
  # Restore previous span
  $hub->get_scope()->set_span($previous_span);
  
  croak $error if $error;
  return $result;
}

=head2 Batch Operations

=head3 start_batch($batch_name, $items, $options = {})

Start a batch operation span that tracks multiple items.

  my $batch = $spans->start_batch('email.send_batch', \@emails, {
    tags => { email_type => 'notification' }
  });
  
  for my $email (@emails) {
    $batch->process_item($email->{id}, sub {
      # Send email
    });
  }
  
  $batch->finish();

=cut

sub start_batch ($self, $batch_name, $items, $options = {}) {
  return undef unless $self->enabled;
  
  my $batch_span = $self->start_span(
    'batch.operation',
    $batch_name,
    {
      %$options,
      data => {
        %{$options->{data} || {}},
        batch_size => scalar(@$items),
        batch_name => $batch_name
      }
    }
  );
  
  return Sentry::Instrumentation::Spans::BatchSpan->new(
    span => $batch_span,
    manager => $self,
    items => $items,
    batch_name => $batch_name
  );
}

=head2 Error Handling

=head3 capture_span_exception($span, $exception, $data = {})

Capture an exception within a span context.

  eval { risky_operation() };
  if (my $error = $@) {
    $spans->capture_span_exception($span, $error, { context => 'critical' });
  }

=cut

sub capture_span_exception ($self, $span, $exception, $data = {}) {
  my $actual_span = $span->can('span') ? $span->span : $span;
  
  $actual_span->set_status('internal_error');
  $actual_span->set_tag('error', 1);
  $actual_span->set_data('error.message', "$exception");
  
  # Add error data
  for my $key (keys %$data) {
    $actual_span->set_data("error.$key", $data->{$key});
  }
  
  # Capture exception through Sentry
  my $hub = Sentry::Hub->get_current_hub();
  $self->with_span_context($span, sub {
    $hub->capture_exception($exception);
  });
  
  return $self;
}

=head2 Cleanup

=head3 finish_all_spans()

Finish all active spans (useful for cleanup).

  $spans->finish_all_spans();

=cut

sub finish_all_spans ($self) {
  for my $span (@{$self->_active_spans}) {
    $span->finish() if $span && !$span->timestamp;
  }
  $self->_active_spans([]);
  return $self;
}

# Custom span wrapper class
package Sentry::Instrumentation::Spans::CustomSpan {
  use Mojo::Base -base, -signatures;
  
  has 'span';
  has 'manager';
  
  # Delegate methods to underlying span
  sub set_tag ($self, $key, $value) {
    $self->span->set_tag($key, $value);
    return $self;
  }
  
  sub set_data ($self, $key, $value) {
    my $data = $self->span->data || {};
    $data->{$key} = $value;
    $self->span->data($data);
    return $self;
  }
  
  sub get_data ($self, $key = undef) {
    my $data = $self->span->data || {};
    return $key ? $data->{$key} : $data;
  }
  
  sub data ($self, $data = undef) {
    if (defined $data) {
      $self->span->data($data);
      return $self;
    }
    return $self->span->data;
  }
  
  sub set_status ($self, $status) {
    $self->span->status($status);
    return $self;
  }
  
  sub add_breadcrumb ($self, $message, $data = {}) {
    my $hub = Sentry::Hub->get_current_hub();
    $hub->add_breadcrumb({
      type => 'default',
      category => 'custom.span',
      message => $message,
      level => 'info',
      data => $data
    });
    return $self;
  }
  
  sub start_child ($self, $op, $description = undef, $options = {}) {
    return $self->manager->start_span($op, $description, $options);
  }
  
  sub finish ($self) {
    $self->span->finish();
    
    # Remove from active spans if auto-finish is enabled
    if ($self->manager->auto_finish) {
      my $active = $self->manager->_active_spans;
      @$active = grep { $_ ne $self->span } @$active;
    }
    
    return $self;
  }
  
  # Timing helper
  sub time_child ($self, $name, $code, $options = {}) {
    return $self->manager->with_span_context($self, sub {
      return $self->manager->trace($name, $code, $options);
    });
  }
}

# Batch span class
package Sentry::Instrumentation::Spans::BatchSpan {
  use Mojo::Base 'Sentry::Instrumentation::Spans::CustomSpan', -signatures;
  
  has 'items';
  has 'batch_name';
  has '_processed_count' => 0;
  has '_error_count' => 0;
  
  sub process_item ($self, $item_id, $code, $options = {}) {
    my $item_span = $self->start_child(
      'batch.item',
      "Process item: $item_id",
      {
        %$options,
        tags => {
          %{$options->{tags} || {}},
          batch_name => $self->batch_name,
          item_id => $item_id
        }
      }
    );
    
    eval {
      my $result = $code->();
      $self->{_processed_count}++;
      $item_span->set_status('ok');
      $item_span->set_data('result', 'success');
      return $result;
    };
    
    if (my $error = $@) {
      $self->{_error_count}++;
      $item_span->set_status('internal_error');
      $item_span->set_tag('error', 1);
      $item_span->set_data('error.message', "$error");
    }
    
    $item_span->finish();
  }
  
  sub finish ($self) {
    # Update batch statistics
    $self->set_data('processed_count', $self->{_processed_count});
    $self->set_data('error_count', $self->{_error_count});
    $self->set_data('success_rate', 
      $self->{_processed_count} > 0 ? 
        ($self->{_processed_count} - $self->{_error_count}) / $self->{_processed_count} : 0);
    
    return $self->SUPER::finish();
  }
}

1;

=head1 SEE ALSO

L<Sentry::Tracing::Span>, L<Sentry::Tracing::Transaction>, L<Sentry::Instrumentation::Metrics>

=head1 AUTHOR

Generated for Sentry Perl SDK Modernization

=cut