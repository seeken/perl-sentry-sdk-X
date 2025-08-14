package Sentry::Integration::DBI;
use Mojo::Base 'Sentry::Integration::Base', -signatures;

use Mojo::Util qw(dumper monkey_patch);
use Time::HiRes;

has breadcrumbs => 1;
has tracing     => 1;

# DBI is special. Classes are generated on-the-fly.
sub around ($package, $method, $cb) {
  ## no critic (TestingAndDebugging::ProhibitNoStrict, TestingAndDebugging::ProhibitNoWarnings, TestingAndDebugging::ProhibitProlongedStrictureOverride)
  no strict 'refs';
  no warnings 'redefine';

  my $symbol = join('::', $package, $method);

  my $orig = \&{$symbol};
  *{$symbol} = sub { $cb->($orig, @_) };

  return;
}

sub setup_once ($self, $add_global_event_processor, $get_current_hub) {
  return if (!$self->breadcrumbs && !$self->tracing);

  # Enhanced DBI::db->do method
  around('DBI::db', do => sub ($orig, $dbh, $statement, @args) {
    my $hub = $get_current_hub->();
    my $span;

    if ($self->tracing && (my $parent_span = $hub->get_scope()->get_span)) {
      # Parse statement to get operation
      my $operation = $self->_extract_sql_operation($statement);
      my $table = $self->_extract_table_name($statement);
      
      $span = $parent_span->start_child({
        op => 'db.query',
        description => $self->_truncate_sql($statement),
        data => {
          # OpenTelemetry semantic conventions
          'db.system' => $self->_get_db_system($dbh),
          'db.operation' => $operation,
          'db.collection.name' => $table,
          'db.name' => $dbh->{Name} // 'unknown',
          'server.address' => $self->_extract_host($dbh),
          'server.port' => $self->_extract_port($dbh),
          
          # Additional context
          'db.statement' => $self->_should_capture_statement() ? $statement : undef,
          'db.connection_id' => "$dbh", # stringify dbh reference
          'thread.id' => $$, # process id as thread id
        },
      });
    }

    my $start_time = Time::HiRes::time();
    my $value = $orig->($dbh, $statement, @args);
    my $duration = Time::HiRes::time() - $start_time;

    # Enhanced breadcrumb with more context
    $hub->add_breadcrumb({
      type => 'query',
      category => 'db.query',
      message => $self->_truncate_sql($statement),
      level => 'info',
      data => {
        'db.system' => $self->_get_db_system($dbh),
        'db.operation' => $self->_extract_sql_operation($statement),
        'db.collection.name' => $self->_extract_table_name($statement),
        'duration_ms' => int($duration * 1000),
        'rows_affected' => $value // 0,
      },
    }) if $self->breadcrumbs;

    if ($span) {
      # Update span data with execution results
      my $data = $span->data || {};
      $data->{'db.rows_affected'} = $value // 0;
      $data->{'duration_ms'} = int($duration * 1000);
      $span->data($data);
      
      $span->finish();
    }

    return $value;
  });

  # Enhanced DBI::st->execute method
  around('DBI::st', execute => sub ($orig, $sth, @args) {
    my $statement = $sth->{Statement};
    my $hub = $get_current_hub->();
    my $span;

    if ($self->tracing && (my $parent_span = $hub->get_scope()->get_span)) {
      my $operation = $self->_extract_sql_operation($statement);
      my $table = $self->_extract_table_name($statement);
      
      $span = $parent_span->start_child({
        op => 'db.query',
        description => $self->_truncate_sql($statement),
        data => {
          'db.system' => $self->_get_db_system($sth->{Database}),
          'db.operation' => $operation,
          'db.collection.name' => $table,
          'db.name' => $sth->{Database}->{Name} // 'unknown',
          'server.address' => $self->_extract_host($sth->{Database}),
          'server.port' => $self->_extract_port($sth->{Database}),
          'db.statement' => $self->_should_capture_statement() ? $statement : undef,
          'db.parameter_count' => scalar(@args),
          'thread.id' => $$,
        },
      });
    }

    my $start_time = Time::HiRes::time();
    my $value = $orig->($sth, @args);
    my $duration = Time::HiRes::time() - $start_time;

    $hub->add_breadcrumb({
      type => 'query',
      category => 'db.query',
      message => $self->_truncate_sql($statement),
      level => 'info',
      data => {
        'db.system' => $self->_get_db_system($sth->{Database}),
        'db.operation' => $self->_extract_sql_operation($statement),
        'db.collection.name' => $self->_extract_table_name($statement),
        'duration_ms' => int($duration * 1000),
        'rows_affected' => eval { $sth->rows } // 0,
        'parameter_count' => scalar(@args),
      },
    }) if $self->breadcrumbs;

    if ($span) {
      # Update span data with execution results
      my $data = $span->data || {};
      $data->{'db.rows_affected'} = eval { $sth->rows } // 0;
      $data->{'duration_ms'} = int($duration * 1000);
      $span->data($data);
      
      $span->finish();
    }

    return $value;
  });
}

# Helper methods for database telemetry
sub _get_db_system ($self, $dbh) {
  my $driver = eval { $dbh->{Driver}->{Name} } // 'unknown';
  return {
    'mysql' => 'mysql',
    'Pg' => 'postgresql',
    'SQLite' => 'sqlite',
    'Oracle' => 'oracle',
    'ODBC' => 'mssql',
  }->{$driver} // lc($driver);
}

sub _extract_sql_operation ($self, $sql) {
  return 'unknown' unless $sql;
  if ($sql =~ /^\s*(SELECT|INSERT|UPDATE|DELETE|CREATE|DROP|ALTER|TRUNCATE)\b/i) {
    return uc($1);
  }
  return 'unknown';
}

sub _extract_table_name ($self, $sql) {
  return undef unless $sql;
  # Simple regex to extract table name - can be enhanced
  if ($sql =~ /(?:FROM|INTO|UPDATE|TABLE)\s+`?(\w+)`?/i) {
    return $1;
  }
  return undef;
}

sub _extract_host ($self, $dbh) {
  my $name = eval { $dbh->{Name} } // '';
  if ($name =~ /host=([^;]+)/i) {
    return $1;
  }
  return 'localhost';
}

sub _extract_port ($self, $dbh) {
  my $name = eval { $dbh->{Name} } // '';
  if ($name =~ /port=(\d+)/i) {
    return int($1);
  }
  return undef;
}

sub _truncate_sql ($self, $sql, $max_length = 100) {
  return undef unless $sql;
  $sql =~ s/\s+/ /g;  # Normalize whitespace
  return length($sql) > $max_length ? substr($sql, 0, $max_length) . '...' : $sql;
}

sub _should_capture_statement ($self) {
  my $hub = Sentry::Hub->get_current_hub();
  my $client = $hub->client;
  return $client && $client->_options->{send_default_pii} // 0;
}

1;
