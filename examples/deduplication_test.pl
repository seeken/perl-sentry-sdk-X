#!/usr/bin/env perl

use strict;
use warnings;
use feature 'say';

use lib '../lib';
use Sentry::SDK;
use Sentry::Integration::DBI;
use DBI;

# Test with explicit integration configuration to avoid duplicates
Sentry::SDK->init({
  dsn => $ENV{SENTRY_DSN} || 'https://bc1b329862866abb9c8f70c5dac940aa@sentry.cgtmigration.com/9',
  release => 'perl-sdk@1.3.9-dedup-test',
  traces_sample_rate => 1.0,
  
  # Disable ALL default integrations and only enable what we explicitly want
  disabled_integrations => ['DieHandler', 'DBI', 'LwpUserAgent', 'MojoUserAgent', 'MojoTemplate'],
  
  integrations => [
    Sentry::Integration::DBI->new({
      tracing => 1,
      breadcrumbs => 1,
      track_connection_lifecycle => 1,
    }),
  ],
});

say "🧪 Testing Database Integration Deduplication";

# Start transaction
my $transaction = Sentry::SDK->start_transaction({
  name => 'dedup_test',
  op => 'test',
});

Sentry::Hub->get_current_hub()->get_scope()->set_span($transaction);

# Single database operation
my $dbh = DBI->connect("dbi:SQLite:dbname=:memory:", "", "", {RaiseError => 1});
$dbh->do("CREATE TABLE test (id INTEGER)");
$dbh->do("INSERT INTO test VALUES (1)");
my $sth = $dbh->prepare("SELECT * FROM test");
$sth->execute();
$dbh->disconnect();

$transaction->finish();

say "✅ Deduplication test completed - check envelope size in output";