package Sentry::Integration::DBI;
use Mojo::Base 'Sentry::Integration::Base', -signatures;

use Mojo::Util qw(dumper monkey_patch);
use Sentry::SDK;
use Time::HiRes;

has breadcrumbs => 1;
has tracing     => 1;
has slow_query_threshold => 1.0;  # seconds
has capture_query_parameters => 0;
has track_connection_lifecycle => 1;
has max_query_length => 2048;

# Connection tracking for telemetry
has _connection_registry => sub { {} };
has _connection_stats => sub { {} };

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

  # Track DBI->connect for connection lifecycle monitoring
  if ($self->track_connection_lifecycle) {
    around('DBI', connect => sub {
      my ($orig, $class, $dsn, $username, $password, $attr) = @_;
      $attr //= {};
      my $start_time = Time::HiRes::time();
      my $hub = $get_current_hub->();
      my $span;

      if ($self->tracing && (my $parent_span = $hub->get_scope()->get_span)) {
        $span = $parent_span->start_child({
          op => 'db.connection',
          description => 'Database connection',
          data => {
            'db.system' => $self->_get_db_system_from_dsn($dsn),
            'db.name' => $self->_extract_db_name($dsn),
            'server.address' => $self->_extract_host_from_dsn($dsn),
            'server.port' => $self->_extract_port_from_dsn($dsn),
            'db.user' => $username // 'unknown',
            'db.connection_string' => $self->_sanitize_dsn($dsn),
            'thread.id' => $$,
          },
        });
      }

      my $dbh = $orig->($class, $dsn, $username, $password, $attr);
      my $duration = Time::HiRes::time() - $start_time;

      if ($dbh) {
        # Register connection for tracking
        my $connection_id = "$dbh";
        $self->_connection_registry->{$connection_id} = {
          dsn => $dsn,
          connected_at => time(),
          query_count => 0,
          total_query_time => 0,
          slow_query_count => 0,
          error_count => 0,
          last_activity => time(),
        };

        # Add breadcrumb for successful connection
        $hub->add_breadcrumb({
          type => 'info',
          category => 'db.connection',
          message => 'Database connection established',
          level => 'info',
          data => {
            'db.system' => $self->_get_db_system_from_dsn($dsn),
            'db.name' => $self->_extract_db_name($dsn),
            'server.address' => $self->_extract_host_from_dsn($dsn),
            'duration_ms' => int($duration * 1000),
            'connection_id' => $connection_id,
          },
        }) if $self->breadcrumbs;

        if ($span) {
          my $data = $span->data || {};
          $data->{'duration_ms'} = int($duration * 1000);
          $data->{'db.connection_id'} = $connection_id;
          $span->data($data);
          $span->set_tag('db.connection.status', 'success');
          $span->finish();
        }
      } else {
        # Connection failed
        my $error = $DBI::errstr || 'Unknown connection error';
        
        $hub->add_breadcrumb({
          type => 'error',
          category => 'db.connection',
          message => "Database connection failed: $error",
          level => 'error',
          data => {
            'db.system' => $self->_get_db_system_from_dsn($dsn),
            'server.address' => $self->_extract_host_from_dsn($dsn),
            'duration_ms' => int($duration * 1000),
            'error' => $error,
          },
        }) if $self->breadcrumbs;

        if ($span) {
          my $data = $span->data || {};
          $data->{'duration_ms'} = int($duration * 1000);
          $data->{'error'} = $error;
          $span->data($data);
          $span->set_tag('db.connection.status', 'error');
          $span->finish();
        }

        # Capture connection failure as an event
        Sentry::SDK->capture_message(
          "Database connection failed: $error",
          {
            level => 'error',
            contexts => {
              database => {
                dsn => $self->_sanitize_dsn($dsn),
                system => $self->_get_db_system_from_dsn($dsn),
                duration_ms => int($duration * 1000),
              }
            },
            tags => {
              db_system => $self->_get_db_system_from_dsn($dsn),
              connection_error => 1,
            }
          }
        );
      }

      return $dbh;
    });

    # Track connection disconnection
    around('DBI::db', disconnect => sub {
      my ($orig, $dbh) = @_;
      my $connection_id = "$dbh";
      my $stats = $self->_connection_registry->{$connection_id};
      my $hub = $get_current_hub->();

      if ($stats && $self->breadcrumbs) {
        my $lifetime = time() - $stats->{connected_at};
        $hub->add_breadcrumb({
          type => 'info',
          category => 'db.connection',
          message => 'Database connection closed',
          level => 'info',
          data => {
            'db.system' => $self->_get_db_system($dbh),
            'connection_id' => $connection_id,
            'connection_lifetime_seconds' => $lifetime,
            'total_queries' => $stats->{query_count},
            'total_query_time_ms' => int($stats->{total_query_time} * 1000),
            'slow_queries' => $stats->{slow_query_count},
            'errors' => $stats->{error_count},
          },
        });
      }

      # Clean up connection registry
      delete $self->_connection_registry->{$connection_id};
      
      return $orig->($dbh);
    });
  }

  # Enhanced DBI::db->do method with comprehensive monitoring
  around('DBI::db', do => sub {
    my ($orig, $dbh, $statement, $attr, @bind_values) = @_;
    my $hub = $get_current_hub->();
    my $span;
    my $connection_id = "$dbh";

    # Update connection stats
    my $conn_stats = $self->_connection_registry->{$connection_id};
    if ($conn_stats) {
      $conn_stats->{query_count}++;
      $conn_stats->{last_activity} = time();
    }

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
          'db.statement' => $self->_should_capture_statement() ? 
            $self->_truncate_sql($statement, $self->max_query_length) : undef,
          'db.connection_id' => $connection_id,
          'thread.id' => $$,
          'db.parameter_count' => scalar(@bind_values),
        },
      });

      # Add parameters if enabled and not PII-sensitive
      if ($self->capture_query_parameters && @bind_values) {
        my $data = $span->data || {};
        $data->{'db.parameters'} = $self->_sanitize_parameters(\@bind_values);
        $span->data($data);
      }
    }

    my $start_time = Time::HiRes::time();
    my ($value, $error);
    
    eval {
      $value = $orig->($dbh, $statement, $attr, @bind_values);
      1;
    } or do {
      $error = $@ || $DBI::errstr || 'Unknown database error';
    };
    
    my $duration = Time::HiRes::time() - $start_time;
    my $is_slow_query = $duration >= $self->slow_query_threshold;

    # Update connection stats
    if ($conn_stats) {
      $conn_stats->{total_query_time} += $duration;
      if ($is_slow_query) {
        $conn_stats->{slow_query_count}++;
      }
      if ($error) {
        $conn_stats->{error_count}++;
      }
    }

    # Enhanced breadcrumb with more context
    my $breadcrumb_level = $error ? 'error' : ($is_slow_query ? 'warning' : 'info');
    $hub->add_breadcrumb({
      type => 'query',
      category => 'db.query',
      message => $self->_truncate_sql($statement),
      level => $breadcrumb_level,
      data => {
        'db.system' => $self->_get_db_system($dbh),
        'db.operation' => $self->_extract_sql_operation($statement),
        'db.collection.name' => $self->_extract_table_name($statement),
        'duration_ms' => int($duration * 1000),
        'rows_affected' => $error ? 0 : ($value // 0),
        'is_slow_query' => $is_slow_query ? 1 : 0,
        'connection_id' => $connection_id,
        $error ? ('error' => $error) : (),
      },
    }) if $self->breadcrumbs;

    if ($span) {
      # Update span data with execution results
      my $data = $span->data || {};
      $data->{'db.rows_affected'} = $error ? 0 : ($value // 0);
      $data->{'duration_ms'} = int($duration * 1000);
      $data->{'is_slow_query'} = $is_slow_query ? 1 : 0;
      
      if ($error) {
        $data->{'error'} = $error;
        $span->set_tag('error', 1);
        $span->set_tag('db.error.type', $self->_classify_db_error($error));
      }
      
      $span->data($data);
      $span->set_tag('db.slow_query', 1) if $is_slow_query;
      $span->finish();
    }

    # Capture slow queries as separate events
    if ($is_slow_query && !$error) {
      $self->_capture_slow_query($statement, $duration, $dbh, \@bind_values);
    }

    # Capture database errors
    if ($error) {
      $self->_capture_database_error($statement, $error, $duration, $dbh, \@bind_values);
      die $error;  # Re-throw the error
    }

    return $value;
  });

  # Enhanced DBI::st->execute method with comprehensive monitoring
  around('DBI::st', execute => sub {
    my ($orig, $sth, @bind_values) = @_;
    my $statement = $sth->{Statement};
    my $dbh = $sth->{Database};
    my $hub = $get_current_hub->();
    my $span;
    my $connection_id = "$dbh";

    # Update connection stats
    my $conn_stats = $self->_connection_registry->{$connection_id};
    if ($conn_stats) {
      $conn_stats->{query_count}++;
      $conn_stats->{last_activity} = time();
    }

    if ($self->tracing && (my $parent_span = $hub->get_scope()->get_span)) {
      my $operation = $self->_extract_sql_operation($statement);
      my $table = $self->_extract_table_name($statement);
      
      $span = $parent_span->start_child({
        op => 'db.query',
        description => $self->_truncate_sql($statement),
        data => {
          'db.system' => $self->_get_db_system($dbh),
          'db.operation' => $operation,
          'db.collection.name' => $table,
          'db.name' => $dbh->{Name} // 'unknown',
          'server.address' => $self->_extract_host($dbh),
          'server.port' => $self->_extract_port($dbh),
          'db.statement' => $self->_should_capture_statement() ? 
            $self->_truncate_sql($statement, $self->max_query_length) : undef,
          'db.parameter_count' => scalar(@bind_values),
          'db.connection_id' => $connection_id,
          'thread.id' => $$,
        },
      });

      # Add parameters if enabled
      if ($self->capture_query_parameters && @bind_values) {
        my $data = $span->data || {};
        $data->{'db.parameters'} = $self->_sanitize_parameters(\@bind_values);
        $span->data($data);
      }
    }

    my $start_time = Time::HiRes::time();
    my ($value, $error);
    
    eval {
      $value = $orig->($sth, @bind_values);
      1;
    } or do {
      $error = $@ || $sth->errstr || $DBI::errstr || 'Unknown database error';
    };
    
    my $duration = Time::HiRes::time() - $start_time;
    my $is_slow_query = $duration >= $self->slow_query_threshold;
    my $rows_affected = 0;

    # Get rows affected if query succeeded
    if (!$error) {
      $rows_affected = eval { $sth->rows } // 0;
    }

    # Update connection stats
    if ($conn_stats) {
      $conn_stats->{total_query_time} += $duration;
      if ($is_slow_query) {
        $conn_stats->{slow_query_count}++;
      }
      if ($error) {
        $conn_stats->{error_count}++;
      }
    }

    my $breadcrumb_level = $error ? 'error' : ($is_slow_query ? 'warning' : 'info');
    $hub->add_breadcrumb({
      type => 'query',
      category => 'db.query',
      message => $self->_truncate_sql($statement),
      level => $breadcrumb_level,
      data => {
        'db.system' => $self->_get_db_system($dbh),
        'db.operation' => $self->_extract_sql_operation($statement),
        'db.collection.name' => $self->_extract_table_name($statement),
        'duration_ms' => int($duration * 1000),
        'rows_affected' => $rows_affected,
        'parameter_count' => scalar(@bind_values),
        'is_slow_query' => $is_slow_query ? 1 : 0,
        'connection_id' => $connection_id,
        $error ? ('error' => $error) : (),
      },
    }) if $self->breadcrumbs;

    if ($span) {
      # Update span data with execution results
      my $data = $span->data || {};
      $data->{'db.rows_affected'} = $rows_affected;
      $data->{'duration_ms'} = int($duration * 1000);
      $data->{'is_slow_query'} = $is_slow_query ? 1 : 0;
      
      if ($error) {
        $data->{'error'} = $error;
        $span->set_tag('error', 1);
        $span->set_tag('db.error.type', $self->_classify_db_error($error));
      }
      
      $span->data($data);
      $span->set_tag('db.slow_query', 1) if $is_slow_query;
      $span->finish();
    }

    # Capture slow queries
    if ($is_slow_query && !$error) {
      $self->_capture_slow_query($statement, $duration, $dbh, \@bind_values);
    }

    # Capture database errors
    if ($error) {
      $self->_capture_database_error($statement, $error, $duration, $dbh, \@bind_values);
      die $error;  # Re-throw the error
    }

    return $value;
  });
}

# Enhanced helper methods for database telemetry and monitoring

sub _get_db_system_from_dsn ($self, $dsn) {
  return 'unknown' unless $dsn;
  if ($dsn =~ /^dbi:(\w+):/i) {
    my $driver = lc($1);
    return {
      'mysql' => 'mysql',
      'pg' => 'postgresql', 
      'sqlite' => 'sqlite',
      'oracle' => 'oracle',
      'odbc' => 'mssql',
      'sybase' => 'mssql',
    }->{$driver} // $driver;
  }
  return 'unknown';
}

sub _extract_db_name ($self, $dsn) {
  return undef unless $dsn;
  if ($dsn =~ /(?:database|dbname|db)=([^;]+)/i) {
    return $1;
  }
  return undef;
}

sub _extract_host_from_dsn ($self, $dsn) {
  return 'localhost' unless $dsn;
  if ($dsn =~ /(?:host|server)=([^;]+)/i) {
    return $1;
  }
  return 'localhost';
}

sub _extract_port_from_dsn ($self, $dsn) {
  return undef unless $dsn;
  if ($dsn =~ /port=(\d+)/i) {
    return int($1);
  }
  return undef;
}

sub _sanitize_dsn ($self, $dsn) {
  my $sanitized = $dsn;
  # Remove password from DSN for logging
  $sanitized =~ s/(password|pwd)=[^;]*/$1=***/gi;
  return $sanitized;
}

sub _capture_slow_query ($self, $statement, $duration, $dbh, $bind_values) {
  my $sanitized_statement = $self->_should_capture_statement() ? 
    $self->_truncate_sql($statement, $self->max_query_length) : 
    $self->_extract_sql_operation($statement) . ' query';

  Sentry::SDK->capture_message(
    "Slow database query detected",
    {
      level => 'warning',
      contexts => {
        database => {
          system => $self->_get_db_system($dbh),
          name => $dbh->{Name} // 'unknown',
          statement => $sanitized_statement,
          duration_ms => int($duration * 1000),
          threshold_ms => int($self->slow_query_threshold * 1000),
          operation => $self->_extract_sql_operation($statement),
          table => $self->_extract_table_name($statement),
          parameter_count => scalar(@$bind_values),
        }
      },
      tags => {
        db_system => $self->_get_db_system($dbh),
        db_operation => $self->_extract_sql_operation($statement),
        slow_query => 1,
        performance_issue => 1,
      }
    }
  );
}

sub _capture_database_error ($self, $statement, $error, $duration, $dbh, $bind_values) {
  my $error_type = $self->_classify_db_error($error);
  my $sanitized_statement = $self->_should_capture_statement() ? 
    $self->_truncate_sql($statement, $self->max_query_length) : 
    $self->_extract_sql_operation($statement) . ' query';

  Sentry::SDK->capture_message(
    "Database query error: $error",
    {
      level => 'error',
      contexts => {
        database => {
          system => $self->_get_db_system($dbh),
          name => $dbh->{Name} // 'unknown',
          statement => $sanitized_statement,
          error => $error,
          error_type => $error_type,
          duration_ms => int($duration * 1000),
          operation => $self->_extract_sql_operation($statement),
          table => $self->_extract_table_name($statement),
          parameter_count => scalar(@$bind_values),
        }
      },
      tags => {
        db_system => $self->_get_db_system($dbh),
        db_operation => $self->_extract_sql_operation($statement),
        db_error_type => $error_type,
        database_error => 1,
      }
    }
  );
}

sub _classify_db_error ($self, $error) {
  return 'unknown' unless $error;
  
  # Common database error patterns
  if ($error =~ /duplicate|unique constraint|primary key/i) {
    return 'constraint_violation';
  } elsif ($error =~ /foreign key|referential integrity/i) {
    return 'foreign_key_violation';
  } elsif ($error =~ /syntax error|sql syntax/i) {
    return 'syntax_error';
  } elsif ($error =~ /permission|access denied|unauthorized/i) {
    return 'permission_error';
  } elsif ($error =~ /connection|timeout|lost connection/i) {
    return 'connection_error';
  } elsif ($error =~ /deadlock/i) {
    return 'deadlock';
  } elsif ($error =~ /lock|locked/i) {
    return 'lock_timeout';
  } elsif ($error =~ /table.*not exist|unknown table/i) {
    return 'table_not_found';
  } elsif ($error =~ /column.*not exist|unknown column/i) {
    return 'column_not_found';
  }
  
  return 'general_error';
}

sub _sanitize_parameters ($self, $params) {
  return [] unless $params && @$params;
  
  # Limit parameter logging and sanitize potentially sensitive data
  my @sanitized;
  my $max_params = 10;  # Limit logged parameters
  
  for my $i (0 .. min($#$params, $max_params - 1)) {
    my $param = $params->[$i];
    if (!defined $param) {
      push @sanitized, undef;
    } elsif (length($param) > 100) {
      push @sanitized, substr($param, 0, 100) . '...';
    } elsif ($param =~ /password|token|secret|key/i) {
      push @sanitized, '***';
    } else {
      push @sanitized, $param;
    }
  }
  
  if (@$params > $max_params) {
    push @sanitized, "... (" . (@$params - $max_params) . " more parameters)";
  }
  
  return \@sanitized;
}

# Connection pool and health monitoring
sub get_connection_stats ($self) {
  return {
    active_connections => scalar(keys %{$self->_connection_registry}),
    total_connections => scalar(keys %{$self->_connection_stats}),
    connection_details => { %{$self->_connection_registry} },
  };
}

sub get_performance_metrics ($self) {
  my $stats = $self->_connection_registry;
  my $total_queries = 0;
  my $total_time = 0;
  my $slow_queries = 0;
  my $errors = 0;
  
  for my $conn_stats (values %$stats) {
    $total_queries += $conn_stats->{query_count};
    $total_time += $conn_stats->{total_query_time};
    $slow_queries += $conn_stats->{slow_query_count};
    $errors += $conn_stats->{error_count};
  }
  
  return {
    total_queries => $total_queries,
    total_time_seconds => $total_time,
    average_query_time_ms => $total_queries ? int(($total_time / $total_queries) * 1000) : 0,
    slow_queries => $slow_queries,
    error_count => $errors,
    error_rate => $total_queries ? ($errors / $total_queries) : 0,
  };
}

sub min { $_[0] < $_[1] ? $_[0] : $_[1] }
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
