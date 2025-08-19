#!/usr/bin/env perl

=head1 NAME

Phase 4 Demo - Enhanced Database Integration & Query Performance Monitoring

=head1 DESCRIPTION

Demonstrates comprehensive database integration with:
- Connection lifecycle tracking
- Query performance monitoring with slow query detection
- Database error capture and classification
- Connection pool telemetry
- Query parameter sanitization
- Distributed tracing for database operations

=cut

use strict;
use warnings;
use feature 'say';

use lib '../lib';

use Sentry::SDK;
use Sentry::Integration::DBI;
use DBI;
use Time::HiRes qw(sleep);
use JSON::PP;

# Initialize Sentry with enhanced database integration
Sentry::SDK->init({
  dsn => $ENV{SENTRY_DSN} || 'https://bc1b329862866abb9c8f70c5dac940aa@sentry.cgtmigration.com/9',
  release => 'perl-sdk@1.3.9-phase4',
  environment => 'development',
  traces_sample_rate => 1.0,
  
  # Enable PII capture for demo (normally disabled in production)
  send_default_pii => 1,
  
  # Disable default DBI integration to avoid duplicates
  disabled_integrations => ['DBI'],
  
  integrations => [
    Sentry::Integration::DBI->new({
      tracing => 1,
      breadcrumbs => 1,
      slow_query_threshold => 0.5,  # 500ms threshold for demo
      capture_query_parameters => 1,
      track_connection_lifecycle => 1,
      max_query_length => 1000,
    }),
  ],
  
  before_send => sub {
    my ($event, $hint) = @_;
    say "📤 Sending event: " . ($event->{message}{formatted} // $event->{transaction} // 'database event');
    return $event;
  },
});

say "🚀 Phase 4 Demo - Enhanced Database Integration";
say "=" x 60;

# Start a parent transaction for database operations
my $transaction = Sentry::SDK->start_transaction({
  name => 'phase4_database_demo',
  op => 'demo.database',
  description => 'Comprehensive database integration demo',
});

Sentry::Hub->get_current_hub()->get_scope()->set_span($transaction);

# Demo 1: SQLite Database Connection and Basic Operations
say "\n📊 Demo 1: Database Connection Lifecycle & Basic Operations";
say "-" x 55;

my $db_span = $transaction->start_child({
  op => 'db.setup',
  description => 'Database setup and basic operations',
});

Sentry::Hub->get_current_hub()->get_scope()->set_span($db_span);

# Create in-memory SQLite database for demo
say "🔌 Connecting to SQLite database...";
my $dbh = DBI->connect(
  "dbi:SQLite:dbname=:memory:",
  "",
  "",
  { 
    RaiseError => 1,
    PrintError => 0,
    AutoCommit => 1,
  }
) or die "Connection failed: $DBI::errstr";

say "✅ Database connection established";

# Create demo table
say "📋 Creating demo table...";
$dbh->do("CREATE TABLE users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name VARCHAR(50) NOT NULL,
  email VARCHAR(100) UNIQUE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  status VARCHAR(20) DEFAULT 'active'
)");

say "✅ Demo table created";

# Insert sample data
say "📝 Inserting sample data...";
my $insert_sth = $dbh->prepare("INSERT INTO users (name, email, status) VALUES (?, ?, ?)");

my @users = (
  ['Alice Johnson', 'alice@example.com', 'active'],
  ['Bob Smith', 'bob@example.com', 'active'],
  ['Carol Davis', 'carol@example.com', 'inactive'],
  ['David Wilson', 'david@example.com', 'active'],
);

for my $user (@users) {
  $insert_sth->execute(@$user);
  say "   ✓ Inserted user: $user->[0]";
}

$db_span->finish();

# Demo 2: Query Performance Monitoring
say "\n⚡ Demo 2: Query Performance Monitoring";
say "-" x 40;

my $perf_span = $transaction->start_child({
  op => 'db.performance',
  description => 'Query performance demonstration',
});

Sentry::Hub->get_current_hub()->get_scope()->set_span($perf_span);

# Fast query
say "🏃 Executing fast query...";
my $fast_sth = $dbh->prepare("SELECT * FROM users WHERE status = ?");
$fast_sth->execute('active');

my @active_users;
while (my $row = $fast_sth->fetchrow_hashref) {
  push @active_users, $row;
}
say "✅ Found " . @active_users . " active users";

# Simulate slow query
say "🐌 Simulating slow query (will trigger slow query detection)...";
my $slow_sth = $dbh->prepare("SELECT *, 
  CASE 
    WHEN name LIKE 'A%' THEN 'Category A'
    WHEN name LIKE 'B%' THEN 'Category B' 
    ELSE 'Other'
  END as category
  FROM users 
  WHERE created_at > datetime('now', '-1 day')
  ORDER BY name");

# Add artificial delay to simulate slow query
my $slow_query_start = Time::HiRes::time();
$slow_sth->execute();
sleep(0.6); # Simulate 600ms processing time
my @slow_results;
while (my $row = $slow_sth->fetchrow_hashref) {
  push @slow_results, $row;
}
my $slow_query_duration = Time::HiRes::time() - $slow_query_start;

say "⚠️  Slow query completed in " . int($slow_query_duration * 1000) . "ms (threshold: 500ms)";
say "✅ Query returned " . @slow_results . " results";

$perf_span->finish();

# Demo 3: Database Error Handling
say "\n🚨 Demo 3: Database Error Handling & Classification";
say "-" x 50;

my $error_span = $transaction->start_child({
  op => 'db.error_handling',
  description => 'Database error handling demonstration',
});

Sentry::Hub->get_current_hub()->get_scope()->set_span($error_span);

# Test different types of database errors
my @error_tests = (
  {
    name => 'Constraint Violation (Duplicate Email)',
    query => "INSERT INTO users (name, email) VALUES ('Test User', 'alice\@example.com')",
    expected_type => 'constraint_violation'
  },
  {
    name => 'Syntax Error',
    query => "SELCT * FROM users WHRE id = 1",
    expected_type => 'syntax_error'  
  },
  {
    name => 'Table Not Found',
    query => "SELECT * FROM nonexistent_table",
    expected_type => 'table_not_found'
  },
  {
    name => 'Column Not Found',
    query => "SELECT nonexistent_column FROM users",
    expected_type => 'column_not_found'
  },
);

for my $test (@error_tests) {
  say "🧪 Testing: $test->{name}";
  eval {
    $dbh->do($test->{query});
  };
  if (my $error = $@) {
    say "   ❌ Expected error caught: " . (split /\n/, $error)[0];
    say "   📊 Error should be classified as: $test->{expected_type}";
  } else {
    say "   ⚠️  Expected error but query succeeded";
  }
  sleep(0.1); # Brief pause between tests
}

$error_span->finish();

# Demo 4: Connection Pool Telemetry (simulate multiple connections)
say "\n🏊 Demo 4: Connection Pool Telemetry";
say "-" x 35;

my $pool_span = $transaction->start_child({
  op => 'db.pool_telemetry',
  description => 'Connection pool monitoring',
});

Sentry::Hub->get_current_hub()->get_scope()->set_span($pool_span);

# Create additional connections to simulate pool
my @additional_connections;
for my $i (1..3) {
  say "🔌 Creating additional connection $i...";
  my $conn = DBI->connect("dbi:SQLite:dbname=:memory:", "", "", {
    RaiseError => 1,
    PrintError => 0,
  });
  
  if ($conn) {
    push @additional_connections, $conn;
    # Do some work with each connection
    $conn->do("CREATE TABLE temp_$i (id INTEGER, data TEXT)");
    $conn->do("INSERT INTO temp_$i VALUES (1, 'test data $i')");
    say "   ✅ Connection $i active and working";
  }
}

# Get integration instance to check connection stats
my $dbi_integration;
for my $integration (@{Sentry::Hub->get_current_hub()->client->_options->{integrations}}) {
  if (ref $integration eq 'Sentry::Integration::DBI') {
    $dbi_integration = $integration;
    last;
  }
}

if ($dbi_integration) {
  my $stats = $dbi_integration->get_connection_stats();
  my $perf_metrics = $dbi_integration->get_performance_metrics();
  
  say "\n📈 Connection Pool Statistics:";
  say "   Active connections: $stats->{active_connections}";
  say "   Total queries: $perf_metrics->{total_queries}";
  say "   Average query time: $perf_metrics->{average_query_time_ms}ms";
  say "   Slow queries: $perf_metrics->{slow_queries}";
  say "   Error rate: " . sprintf("%.2f%%", $perf_metrics->{error_rate} * 100);
}

# Clean up additional connections
for my $i (0..$#additional_connections) {
  say "🔌 Disconnecting additional connection " . ($i + 1) . "...";
  $additional_connections[$i]->disconnect();
}

$pool_span->finish();

# Demo 5: Complex Query with Parameters
say "\n🔍 Demo 5: Complex Queries with Parameter Sanitization";
say "-" x 55;

my $complex_span = $transaction->start_child({
  op => 'db.complex_queries',
  description => 'Complex queries with parameter handling',
});

Sentry::Hub->get_current_hub()->get_scope()->set_span($complex_span);

# Complex query with multiple parameters
say "🔍 Executing complex parameterized query...";
my $complex_query = "SELECT u.*, 
  CASE 
    WHEN u.status = ? THEN 'Active User'
    ELSE 'Inactive User' 
  END as user_type,
  LENGTH(u.name) as name_length,
  UPPER(u.email) as email_upper
  FROM users u 
  WHERE u.name LIKE ? 
    AND u.created_at > datetime('now', ?)
    AND u.status IN (?, ?)
  ORDER BY u.name LIMIT ?";

my @params = (
  'active',           # status comparison  
  'A%',              # name pattern
  '-1 year',         # date comparison
  'active',          # status filter 1
  'inactive',        # status filter 2
  'sensitive_token_12345',  # This should be sanitized
  10                 # limit
);

my $complex_sth = $dbh->prepare($complex_query);
$complex_sth->execute(@params);

my @complex_results;
while (my $row = $complex_sth->fetchrow_hashref) {
  push @complex_results, $row;
}

say "✅ Complex query executed successfully";
say "📊 Parameters included sensitive data that should be sanitized in logs";
say "📋 Query returned " . @complex_results . " results";

$complex_span->finish();

# Clean up
say "\n🧹 Cleanup: Disconnecting from database...";
$dbh->disconnect();
say "✅ Database connection closed";

# Finish the main transaction
$transaction->finish();

say "\n✨ Demo completed! Check your Sentry dashboard for:";
say "   • Connection lifecycle events (connect/disconnect)";
say "   • Query performance metrics with slow query alerts";
say "   • Database error classification and capture";
say "   • Connection pool telemetry and statistics";
say "   • Parameter sanitization in query logs";
say "   • Distributed tracing for all database operations";

say "\n📊 All database operations include comprehensive telemetry";
say "⚡ Performance monitoring with configurable thresholds";
say "🔒 Automatic parameter sanitization for security";

# Keep process alive briefly to ensure all async operations complete
sleep(2);

say "\n🎯 Phase 4 Enhanced Database Integration demo completed!";