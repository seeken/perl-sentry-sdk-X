package Sentry::Crons;
use Mojo::Base -base, -signatures;

use Sentry::Crons::CheckIn;
use Sentry::Crons::Monitor;
use Sentry::Hub;
use Sentry::Logger 'logger';
use Time::HiRes;

# Global storage for active check-ins
our %active_checkins;

sub capture_check_in ($class, $options = {}) {
    my $hub = Sentry::Hub->get_current_hub();
    my $client = $hub->client;
    
    return undef unless $client;
    
    # Handle both hash ref and CheckIn object
    my $checkin;
    if (ref($options) eq 'Sentry::Crons::CheckIn') {
        $checkin = $options;
    } else {
        $checkin = Sentry::Crons::CheckIn->new(%$options);
    }
    
    # Validate required fields
    unless ($checkin->monitor_slug) {
        logger->error("CheckIn requires monitor_slug");
        return undef;
    }
    
    # Store active check-ins for later completion
    if ($checkin->status eq Sentry::Crons::CheckIn::STATUS_IN_PROGRESS) {
        $active_checkins{$checkin->check_in_id} = $checkin;
    }
    
    # Send the check-in
    my $envelope = $client->_prepare_envelope();
    $envelope->add_item('check_in', $checkin->to_envelope_item());
    
    $client->_send_envelope($envelope);
    
    logger->log("Captured check-in: " . $checkin->check_in_id);
    
    return $checkin->check_in_id;
}

sub update_check_in ($class, $check_in_id, $status, $duration_ms = undef) {
    return undef unless $check_in_id && $status;
    
    my $checkin = $active_checkins{$check_in_id};
    unless ($checkin) {
        # We can't update a check-in without the original monitor_slug
        # This would require the user to provide it manually
        logger->warn("Cannot update check-in without original context: $check_in_id");
        return undef;
    }
    
    $checkin->status($status);
    $checkin->duration($duration_ms) if defined $duration_ms;
    
    # Remove from active tracking if completed
    if ($status ne Sentry::Crons::CheckIn::STATUS_IN_PROGRESS) {
        delete $active_checkins{$check_in_id};
    }
    
    return $class->capture_check_in($checkin);
}

sub with_monitor ($class, $monitor_slug, $coderef, $options = {}) {
    return undef unless $monitor_slug && $coderef;
    
    my $environment = $options->{environment};
    my $start_time = Time::HiRes::time();
    
    # Start check-in
    my $checkin = Sentry::Crons::CheckIn->new(
        monitor_slug => $monitor_slug,
        status => Sentry::Crons::CheckIn::STATUS_IN_PROGRESS,
        environment => $environment,
    );
    
    my $check_in_id = $class->capture_check_in($checkin);
    return undef unless $check_in_id;
    
    my $result;
    my $status = Sentry::Crons::CheckIn::STATUS_OK;
    my $error;
    
    eval {
        $result = $coderef->();
    };
    
    if ($@) {
        $error = $@;
        $status = Sentry::Crons::CheckIn::STATUS_ERROR;
        logger->error("Monitor execution failed: $error");
    }
    
    my $duration_ms = int((Time::HiRes::time() - $start_time) * 1000);
    
    # Complete check-in
    $class->update_check_in($check_in_id, $status, $duration_ms);
    
    # Re-throw exception if one occurred
    if ($error) {
        die $error;
    }
    
    return $result;
}

sub upsert_monitor ($class, $monitor_config) {
    my $hub = Sentry::Hub->get_current_hub();
    my $client = $hub->client;
    
    return undef unless $client;
    
    # Handle both hash ref and Monitor object
    my $monitor;
    if (ref($monitor_config) eq 'Sentry::Crons::Monitor') {
        $monitor = $monitor_config;
    } else {
        $monitor = Sentry::Crons::Monitor->new(%$monitor_config);
    }
    
    # Validate the monitor configuration
    my @errors = $monitor->validate();
    if (@errors) {
        logger->error("Monitor validation failed: " . join(", ", @errors));
        return undef;
    }
    
    # Send monitor configuration via envelope
    my $envelope = $client->_prepare_envelope();
    $envelope->add_item('monitor', $monitor->to_monitor_config());
    
    $client->_send_envelope($envelope);
    
    logger->log("Upserted monitor: " . $monitor->slug);
    
    return $monitor->slug;
}

# Clean up any stale check-ins (for long-running processes)
sub cleanup_stale_checkins ($class, $max_age_seconds = 3600) {
    my $cutoff_time = time() - $max_age_seconds;
    
    for my $check_in_id (keys %active_checkins) {
        my $checkin = $active_checkins{$check_in_id};
        if ($checkin->timestamp < $cutoff_time) {
            logger->warn("Cleaning up stale check-in: $check_in_id");
            delete $active_checkins{$check_in_id};
        }
    }
}

# Get active check-ins (for debugging/monitoring)
sub get_active_checkins ($class) {
    return \%active_checkins;
}

1;

__END__

=encoding utf-8

=head1 NAME

Sentry::Crons - Cron monitoring functionality for Sentry

=head1 SYNOPSIS

  use Sentry::Crons;

  # Simple check-in
  my $check_in_id = Sentry::Crons->capture_check_in({
      monitor_slug => 'daily-backup',
      status => 'in_progress',
      environment => 'production',
  });

  # Update the check-in later
  Sentry::Crons->update_check_in($check_in_id, 'ok', 30000);

  # Wrap a cron job automatically
  Sentry::Crons->with_monitor('daily-backup', sub {
      # Your cron job code here
      perform_backup();
  });

  # Configure a monitor
  Sentry::Crons->upsert_monitor({
      slug => 'daily-backup',
      name => 'Daily Database Backup',
      schedule => {
          type => 'crontab',
          value => '0 2 * * *',  # Daily at 2 AM
      },
      checkin_margin => 10,  # 10 minutes
      max_runtime => 60,     # 60 minutes
      timezone => 'UTC',
  });

=head1 DESCRIPTION

This module provides cron monitoring functionality for the Sentry Perl SDK,
allowing you to monitor scheduled tasks and background jobs.

=head1 CLASS METHODS

=head2 capture_check_in

  my $check_in_id = Sentry::Crons->capture_check_in(\%options);

Captures a cron job check-in. Options can include:

=over 4

=item * monitor_slug - Required. The monitor identifier

=item * status - 'in_progress', 'ok', 'error', or 'timeout'

=item * duration - Duration in milliseconds (optional)

=item * environment - Environment name (optional)

=item * contexts - Additional context data (optional)

=back

Returns the check-in ID on success, undef on failure.

=head2 update_check_in

  Sentry::Crons->update_check_in($check_in_id, $status, $duration_ms);

Updates an existing check-in with new status and optional duration.

=head2 with_monitor

  my $result = Sentry::Crons->with_monitor($monitor_slug, sub {
      # Your code here
      return $some_value;
  }, { environment => 'production' });

Wraps code execution with automatic check-in management. Creates an 'in_progress'
check-in before execution and updates it to 'ok' or 'error' based on whether
the code throws an exception.

Returns the result of the wrapped code execution.

=head2 upsert_monitor

  Sentry::Crons->upsert_monitor(\%config);

Creates or updates a monitor configuration. Config can include:

=over 4

=item * slug - Required. Monitor identifier

=item * name - Required. Human-readable name

=item * schedule - Required. Schedule configuration hash

=item * checkin_margin - Grace period in minutes (default: 5)

=item * max_runtime - Maximum runtime in minutes (default: 30)

=item * timezone - Timezone for schedule (default: 'UTC')

=back

Returns the monitor slug on success, undef on failure.

=head2 cleanup_stale_checkins

  Sentry::Crons->cleanup_stale_checkins($max_age_seconds);

Cleans up check-ins that are older than the specified age (default: 1 hour).
Useful for long-running processes to prevent memory leaks.

=head2 get_active_checkins

  my $checkins = Sentry::Crons->get_active_checkins();

Returns a hash reference of currently active check-ins. Useful for debugging.

=head1 AUTHOR

Philipp Busse E<lt>pmb@heise.deE<gt>

=head1 COPYRIGHT

Copyright 2021- Philipp Busse

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
