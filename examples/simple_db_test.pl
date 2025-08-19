#!/usr/bin/env perl

use strict;
use warnings;
use feature 'say';

use lib '../lib';
use Sentry::SDK;
use Sentry::Integration::DBI;
use DBI;
use Time::HiRes qw(sleep);

# Initialize Sentry with database integration
Sentry::SDK->init({
  dsn => $ENV{SENTRY_DSN} || 'https://bc1b329862866abb9c8f70c5dac940aa@sentry.cgtmigration.com/9',
  release => 'perl-sdk@1.3.9-phase4-simple',
  traces_sample_rate => 1.0,
  
  # Disable default DBI integration to avoid duplicates
  disabled_integrations => ['DBI'],
  
  integrations => [
    Sentry::Integration::DBI->new({
      tracing => 1,
      breadcrumbs => 1,
      slow_query_threshold => 0.3,  # 300ms threshold
      track_connection_lifecycle => 1,
    }),
  ],
});

say "🔗 Simple Phase 4 Database Integration Test";

# Start transaction
my $transaction = Sentry::SDK->start_transaction({
  name => 'simple_db_test',
  op => 'test.database',
});

Sentry::Hub->get_current_hub()->get_scope()->set_span($transaction);

# Connect to SQLite
say "🔌 Connecting to database...";
my $dbh = DBI->connect("dbi:SQLite:dbname=:memory:", "", "", {
  RaiseError => 1,
  PrintError => 0,
});

# Create table
say "📋 Creating table...";
$dbh->do("CREATE TABLE test_users (id INTEGER PRIMARY KEY, name TEXT, email TEXT)");

# Insert data
say "📝 Inserting test data...";
$dbh->do("INSERT INTO test_users (name, email) VALUES ('Alice', 'alice\@test.com')");
$dbh->do("INSERT INTO test_users (name, email) VALUES ('Bob', 'bob\@test.com')");

# Query data
say "🔍 Querying data...";
my $sth = $dbh->prepare("SELECT * FROM test_users WHERE name LIKE ?");
$sth->execute('A%');

my @results;
while (my $row = $sth->fetchrow_hashref) {
  push @results, $row;
}
say "✅ Found " . @results . " matching users";

# Simulate slow query
say "🐌 Simulating slow query...";
$dbh->do("SELECT * FROM test_users WHERE name || email LIKE '%test%'");
sleep(0.4);  # Simulate slow processing

# Clean up
say "🧹 Disconnecting...";
$dbh->disconnect();

$transaction->finish();

say "✅ Simple database integration test completed!";