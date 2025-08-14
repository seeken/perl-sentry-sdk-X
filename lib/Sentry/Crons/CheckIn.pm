package Sentry::Crons::CheckIn;
use Mojo::Base -base, -signatures;

use Mojo::JSON qw(encode_json);
use Mojo::Util qw(secure_compare);
use Time::HiRes;
use POSIX qw(strftime);

# UUID v4 generation (simple implementation)
sub _uuid4 {
    my @chars = ('a'..'f', '0'..'9');
    my $uuid = join '', map { $chars[rand @chars] } 1..32;
    $uuid =~ s/^(.{8})(.{4})(.{4})(.{4})(.{12})$/$1-$2-$3-$4-$5/;
    return $uuid;
}

has 'check_in_id' => sub { _uuid4() };
has 'monitor_slug' => undef;
has 'status' => 'in_progress';  # in_progress, ok, error, timeout
has 'duration' => undef;        # Duration in milliseconds
has 'environment' => undef;
has 'contexts' => sub { {} };
has 'timestamp' => sub { time() };

# Status constants
use constant {
    STATUS_IN_PROGRESS => 'in_progress',
    STATUS_OK => 'ok',
    STATUS_ERROR => 'error',
    STATUS_TIMEOUT => 'timeout',
};

sub to_envelope_item ($self) {
    my $item = {
        check_in_id => $self->check_in_id,
        monitor_slug => $self->monitor_slug,
        status => $self->status,
        timestamp => $self->timestamp,
    };
    
    # Add optional fields only if they're defined
    $item->{duration} = $self->duration if defined $self->duration;
    $item->{environment} = $self->environment if defined $self->environment;
    $item->{contexts} = $self->contexts if keys %{$self->contexts};
    
    return $item;
}

sub to_envelope_header ($self) {
    return {
        type => 'check_in',
        length => length(encode_json($self->to_envelope_item())),
    };
}

# Helper method to mark check-in as completed successfully
sub mark_ok ($self, $duration_ms = undef) {
    $self->status(STATUS_OK);
    $self->duration($duration_ms) if defined $duration_ms;
    return $self;
}

# Helper method to mark check-in as failed
sub mark_error ($self, $duration_ms = undef) {
    $self->status(STATUS_ERROR);
    $self->duration($duration_ms) if defined $duration_ms;
    return $self;
}

# Helper method to mark check-in as timed out
sub mark_timeout ($self, $duration_ms = undef) {
    $self->status(STATUS_TIMEOUT);
    $self->duration($duration_ms) if defined $duration_ms;
    return $self;
}

# Add context data for the check-in
sub add_context ($self, $key, $value) {
    $self->contexts->{$key} = $value;
    return $self;
}

1;

__END__

=encoding utf-8

=head1 NAME

Sentry::Crons::CheckIn - Cron job check-in representation

=head1 SYNOPSIS

  use Sentry::Crons::CheckIn;

  # Create a new check-in
  my $checkin = Sentry::Crons::CheckIn->new(
      monitor_slug => 'daily-backup',
      status => 'in_progress',
      environment => 'production',
  );

  # Mark as completed
  $checkin->mark_ok(30000);  # 30 seconds in milliseconds

  # Add context
  $checkin->add_context('backup_size', '1.2GB');

=head1 DESCRIPTION

This class represents a cron job check-in that can be sent to Sentry for monitoring
scheduled tasks and background jobs.

=head1 ATTRIBUTES

=head2 check_in_id

Unique identifier for this check-in. Auto-generated UUID v4 if not provided.

=head2 monitor_slug

The slug identifier for the monitor this check-in belongs to.

=head2 status

Status of the check-in. Can be 'in_progress', 'ok', 'error', or 'timeout'.

=head2 duration

Duration of the job in milliseconds (optional).

=head2 environment

Environment where the job ran (optional).

=head2 contexts

Hash reference containing additional context data.

=head2 timestamp

Unix timestamp when the check-in was created.

=head1 METHODS

=head2 to_envelope_item

Returns the check-in data as a hash reference suitable for envelope serialization.

=head2 to_envelope_header

Returns the envelope header for this check-in.

=head2 mark_ok

  $checkin->mark_ok($duration_ms);

Marks the check-in as successful with optional duration.

=head2 mark_error

  $checkin->mark_error($duration_ms);

Marks the check-in as failed with optional duration.

=head2 mark_timeout

  $checkin->mark_timeout($duration_ms);

Marks the check-in as timed out with optional duration.

=head2 add_context

  $checkin->add_context($key, $value);

Adds context data to the check-in.

=head1 AUTHOR

Philipp Busse E<lt>pmb@heise.deE<gt>

=head1 COPYRIGHT

Copyright 2021- Philipp Busse

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
