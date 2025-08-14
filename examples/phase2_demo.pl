#!/usr/bin/env perl
use strict;
use warnings;
use lib 'lib';

use Sentry::SDK;
use Time::HiRes qw(sleep);

# Initialize Sentry SDK
Sentry::SDK->init({
    dsn => $ENV{SENTRY_DSN} || 'https://demo_key@sentry.io/123456',
    debug => 1,
    environment => 'demo',
});

print "=== Sentry Perl SDK Phase 2 Demo: Cron Monitoring ===\n\n";

# Demo 1: Manual check-in management
print "Demo 1: Manual Check-in Management\n";
print "-----------------------------------\n";

my $check_in_id = Sentry::SDK->capture_check_in({
    monitor_slug => 'manual-job',
    status => 'in_progress',
    environment => 'demo',
});

print "Started manual check-in: $check_in_id\n";

# Simulate some work
print "Performing work...\n";
sleep(2);

# Complete the check-in
Sentry::SDK->update_check_in($check_in_id, 'ok', 2000);
print "Completed manual check-in with 2000ms duration\n\n";

# Demo 2: Automatic monitoring with with_monitor
print "Demo 2: Automatic Monitoring with with_monitor\n";
print "-----------------------------------------------\n";

my $result = Sentry::SDK->with_monitor('auto-job', sub {
    print "Executing automatic monitored job...\n";
    sleep(1.5);
    print "Job processing data...\n";
    sleep(0.5);
    return "Job completed successfully";
});

print "Result: $result\n\n";

# Demo 3: Monitor configuration
print "Demo 3: Monitor Configuration\n";
print "-----------------------------\n";

# Create a daily backup monitor
my $daily_monitor = Sentry::SDK->upsert_monitor({
    slug => 'daily-backup',
    name => 'Daily Database Backup',
    schedule => {
        type => 'crontab',
        value => '0 2 * * *',  # Daily at 2 AM
    },
    checkin_margin => 10,  # 10 minutes grace period
    max_runtime => 60,     # 60 minutes max runtime
    timezone => 'UTC',
});

print "Created daily backup monitor: $daily_monitor\n";

# Create an hourly cleanup monitor
my $hourly_monitor = Sentry::SDK->upsert_monitor({
    slug => 'hourly-cleanup',
    name => 'Hourly Log Cleanup',
    schedule => {
        type => 'interval',
        value => 1,
        unit => 'hour',
    },
    checkin_margin => 5,
    max_runtime => 30,
    timezone => 'UTC',
});

print "Created hourly cleanup monitor: $hourly_monitor\n\n";

# Demo 4: Error handling in monitored jobs
print "Demo 4: Error Handling in Monitored Jobs\n";
print "-----------------------------------------\n";

eval {
    Sentry::SDK->with_monitor('failing-job', sub {
        print "Starting job that will fail...\n";
        sleep(1);
        die "Simulated job failure";
    });
};

if ($@) {
    print "Caught exception: $@";
    print "The failing job was automatically marked as 'error' in Sentry\n\n";
}

# Demo 5: Using the Crons module directly
print "Demo 5: Using Crons Module Directly\n";
print "------------------------------------\n";

use Sentry::Crons;
use Sentry::Crons::CheckIn;
use Sentry::Crons::Monitor;

# Create a check-in object directly
my $checkin = Sentry::Crons::CheckIn->new(
    monitor_slug => 'direct-check',
    status => 'in_progress',
    environment => 'demo',
);

$checkin->add_context('batch_size', 1000);
$checkin->add_context('source', 'csv_import');

my $direct_id = Sentry::Crons->capture_check_in($checkin);
print "Created direct check-in: $direct_id\n";

# Simulate work and complete
sleep(1);
$checkin->mark_ok(1000);
Sentry::Crons->capture_check_in($checkin);
print "Completed direct check-in\n";

# Create a monitor object directly
my $monitor = Sentry::Crons::Monitor->new(
    slug => 'advanced-monitor',
    name => 'Advanced Processing Monitor',
    checkin_margin => 15,
    max_runtime => 120,
    timezone => 'America/New_York',
    failure_issue_threshold => 3,
    recovery_threshold => 2,
);

$monitor->set_crontab_schedule('*/15 * * * *');  # Every 15 minutes

my $advanced_slug = Sentry::Crons->upsert_monitor($monitor);
print "Created advanced monitor: $advanced_slug\n\n";

# Demo 6: Multiple environments
print "Demo 6: Multiple Environments\n";
print "------------------------------\n";

for my $env (qw(staging production)) {
    Sentry::SDK->with_monitor('multi-env-job', sub {
        print "Running job in $env environment\n";
        sleep(0.5);
    }, { environment => $env });
}

print "\nCompleted jobs in multiple environments\n\n";

print "=== Phase 2 Demo Complete ===\n";
print "Check your Sentry dashboard for cron monitoring data!\n";
print "All monitor configurations and check-ins have been sent to Sentry.\n";
