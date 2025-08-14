package Sentry::Crons::Monitor;
use Mojo::Base -base, -signatures;

use Mojo::JSON qw(encode_json);

has 'slug' => undef;           # Monitor identifier
has 'name' => undef;           # Human-readable name
has 'schedule' => sub { {} };  # Schedule configuration
has 'checkin_margin' => 5;     # Minutes of grace period
has 'max_runtime' => 30;       # Maximum runtime in minutes
has 'timezone' => 'UTC';       # Timezone for schedule
has 'failure_issue_threshold' => 1;  # Number of failures before creating issue
has 'recovery_threshold' => 1;       # Number of successes needed for recovery

# Schedule type constants
use constant {
    SCHEDULE_CRONTAB => 'crontab',
    SCHEDULE_INTERVAL => 'interval',
};

# Interval unit constants
use constant {
    UNIT_MINUTE => 'minute',
    UNIT_HOUR => 'hour',
    UNIT_DAY => 'day',
    UNIT_WEEK => 'week',
    UNIT_MONTH => 'month',
    UNIT_YEAR => 'year',
};

sub to_monitor_config ($self) {
    my $config = {
        slug => $self->slug,
        name => $self->name,
        config => {
            schedule => $self->schedule,
            checkin_margin => $self->checkin_margin,
            max_runtime => $self->max_runtime,
            timezone => $self->timezone,
            failure_issue_threshold => $self->failure_issue_threshold,
            recovery_threshold => $self->recovery_threshold,
        },
    };
    
    return $config;
}

# Helper method to set crontab schedule
sub set_crontab_schedule ($self, $crontab) {
    $self->schedule({
        type => SCHEDULE_CRONTAB,
        value => $crontab,
    });
    return $self;
}

# Helper method to set interval schedule
sub set_interval_schedule ($self, $value, $unit) {
    $self->schedule({
        type => SCHEDULE_INTERVAL,
        value => $value,
        unit => $unit,
    });
    return $self;
}

# Validation methods
sub is_valid_crontab ($crontab) {
    # Basic crontab validation - 5 fields separated by spaces
    return 0 unless defined $crontab;
    my @fields = split /\s+/, $crontab;
    return scalar @fields == 5;
}

sub is_valid_interval_unit ($unit) {
    return grep { $_ eq $unit } (UNIT_MINUTE, UNIT_HOUR, UNIT_DAY, UNIT_WEEK, UNIT_MONTH, UNIT_YEAR);
}

sub validate ($self) {
    my @errors;
    
    push @errors, "slug is required" unless defined $self->slug && length $self->slug;
    push @errors, "name is required" unless defined $self->name && length $self->name;
    
    my $schedule = $self->schedule;
    if (!$schedule || !keys %$schedule) {
        push @errors, "schedule is required";
    } else {
        my $type = $schedule->{type};
        my $value = $schedule->{value};
        
        if (!$type) {
            push @errors, "schedule type is required";
        } elsif ($type eq SCHEDULE_CRONTAB) {
            push @errors, "invalid crontab schedule" unless is_valid_crontab($value);
        } elsif ($type eq SCHEDULE_INTERVAL) {
            push @errors, "interval value must be positive integer" 
                unless defined $value && $value =~ /^\d+$/ && $value > 0;
            push @errors, "invalid interval unit" 
                unless is_valid_interval_unit($schedule->{unit});
        } else {
            push @errors, "unknown schedule type: $type";
        }
    }
    
    push @errors, "checkin_margin must be positive" 
        unless $self->checkin_margin > 0;
    push @errors, "max_runtime must be positive" 
        unless $self->max_runtime > 0;
    
    return @errors;
}

1;

__END__

=encoding utf-8

=head1 NAME

Sentry::Crons::Monitor - Cron monitor configuration

=head1 SYNOPSIS

  use Sentry::Crons::Monitor;

  # Create a crontab-based monitor
  my $monitor = Sentry::Crons::Monitor->new(
      slug => 'daily-backup',
      name => 'Daily Database Backup',
      checkin_margin => 10,  # 10 minutes grace period
      max_runtime => 60,     # 60 minutes max runtime
      timezone => 'America/New_York',
  );
  
  $monitor->set_crontab_schedule('0 2 * * *');  # Daily at 2 AM

  # Create an interval-based monitor
  my $monitor2 = Sentry::Crons::Monitor->new(
      slug => 'hourly-cleanup',
      name => 'Hourly Cleanup Task',
  );
  
  $monitor2->set_interval_schedule(1, 'hour');

=head1 DESCRIPTION

This class represents a cron monitor configuration that can be sent to Sentry
to define monitoring parameters for scheduled tasks.

=head1 ATTRIBUTES

=head2 slug

Unique identifier for the monitor.

=head2 name

Human-readable name for the monitor.

=head2 schedule

Hash reference containing schedule configuration. Use helper methods to set this.

=head2 checkin_margin

Number of minutes of grace period before a check-in is considered missed.

=head2 max_runtime

Maximum runtime in minutes before a job is considered hung.

=head2 timezone

Timezone for interpreting the schedule. Defaults to 'UTC'.

=head2 failure_issue_threshold

Number of consecutive failures before creating an issue.

=head2 recovery_threshold

Number of consecutive successes needed to recover from failure state.

=head1 METHODS

=head2 set_crontab_schedule

  $monitor->set_crontab_schedule('0 2 * * *');

Sets a crontab-style schedule (5 fields: minute hour day month weekday).

=head2 set_interval_schedule

  $monitor->set_interval_schedule(30, 'minute');

Sets an interval-style schedule with value and unit.

=head2 to_monitor_config

Returns the monitor configuration as a hash reference suitable for API submission.

=head2 validate

Returns a list of validation errors, or empty list if valid.

=head1 CONSTANTS

=head2 Schedule Types

=over 4

=item * SCHEDULE_CRONTAB - Crontab-style schedule

=item * SCHEDULE_INTERVAL - Interval-based schedule

=back

=head2 Interval Units

=over 4

=item * UNIT_MINUTE, UNIT_HOUR, UNIT_DAY, UNIT_WEEK, UNIT_MONTH, UNIT_YEAR

=back

=head1 AUTHOR

Philipp Busse E<lt>pmb@heise.deE<gt>

=head1 COPYRIGHT

Copyright 2021- Philipp Busse

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
