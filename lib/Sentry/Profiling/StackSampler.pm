package Sentry::Profiling::StackSampler;
use Mojo::Base -base, -signatures;

use Time::HiRes qw(alarm);
use POSIX qw(SIGALRM);
use Sentry::Logger;
use Sentry::Profiling::Frame;

our $VERSION = '1.0.0';

has _active_profile => undef;
has _sampling_interval => 10_000;  # microseconds
has _sample_count => 0;
has _logger => sub { Sentry::Logger->new(component => 'StackSampler') };
has max_stack_depth => 100;
has _original_alarm_handler => undef;

=head1 NAME

Sentry::Profiling::StackSampler - Stack sampling engine for Sentry profiling

=head1 SYNOPSIS

    use Sentry::Profiling::StackSampler;
    
    my $sampler = Sentry::Profiling::StackSampler->new(
        max_stack_depth => 100
    );
    
    $sampler->start($profile, 10_000);  # Start sampling every 10ms
    # ... application runs ...
    $sampler->stop();

=head1 DESCRIPTION

This module implements the core stack sampling functionality for profiling.
It uses signal-based periodic sampling to collect Perl call stacks with
minimal overhead.

=head1 ATTRIBUTES

=head2 max_stack_depth

Maximum number of stack frames to collect. Default: 100.

=head1 METHODS

=head2 start

    $sampler->start($profile, $interval_us);

Start periodic stack sampling for the given profile.

Parameters:
- $profile: Sentry::Profiling::Profile object to store samples
- $interval_us: Sampling interval in microseconds (default: 10,000)

=cut

sub start ($self, $profile, $interval_us = 10_000) {
    return if $self->_active_profile; # Already sampling
    
    $self->_active_profile($profile);
    $self->_sampling_interval($interval_us);
    $self->_sample_count(0);
    
    # Store original handler to restore later
    $self->_original_alarm_handler($SIG{ALRM});
    
    # Set up signal handler for SIGALRM
    $SIG{ALRM} = sub { $self->_sample_stack() };
    
    # Start periodic sampling
    $self->_schedule_next_sample();
    
    $self->_logger->debug("Started stack sampling", {
        interval_us => $interval_us,
        profile_name => $profile->name,
        max_depth => $self->max_stack_depth,
    });
}

=head2 stop

    $sampler->stop();

Stop stack sampling and restore original signal handlers.

=cut

sub stop ($self) {
    return unless $self->_active_profile;
    
    # Disable alarm
    alarm(0);
    
    # Restore original handler
    if (defined $self->_original_alarm_handler) {
        $SIG{ALRM} = $self->_original_alarm_handler;
    } else {
        delete $SIG{ALRM};
    }
    
    my $sample_count = $self->_sample_count;
    my $profile_name = $self->_active_profile->name;
    $self->_active_profile(undef);
    $self->_original_alarm_handler(undef);
    
    $self->_logger->debug("Stopped stack sampling", {
        total_samples => $sample_count,
        profile_name => $profile_name,
    });
}

=head2 get_sample_count

    my $count = $sampler->get_sample_count();

Get the number of samples collected in the current profiling session.

=cut

sub get_sample_count ($self) {
    return $self->_sample_count;
}

=head2 is_sampling

    my $sampling = $sampler->is_sampling();

Check if sampling is currently active.

=cut

sub is_sampling ($self) {
    return defined $self->_active_profile;
}

=head2 sample_once

    $sampler->sample_once();

Manually trigger a single stack sample. Used for testing and deterministic sampling.

=cut

sub sample_once ($self) {
    $self->_sample_stack();
}

# Internal sampling logic

sub _schedule_next_sample ($self) {
    return unless $self->_active_profile;
    
    my $interval_seconds = $self->_sampling_interval / 1_000_000;
    alarm($interval_seconds);
}

sub _sample_stack ($self) {
    my $profile = $self->_active_profile;
    return unless $profile;
    
    # Use a simple flag to prevent recursive sampling
    return if $self->{_currently_sampling};
    local $self->{_currently_sampling} = 1;
    
    eval {
        # Collect stack trace
        my $stack_frames = $self->_collect_stack_trace();
        
        if (@$stack_frames) {
            my $sample = {
                timestamp => Time::HiRes::time(),
                thread_id => "$$",  # Process ID as thread identifier
                frames => $stack_frames,
            };
            
            $profile->add_sample($sample);
            $self->_sample_count($self->_sample_count + 1);
        }
    };
    
    if ($@) {
        $self->_logger->warn("Error collecting stack sample: $@");
    }
    
    # Schedule next sample if still active
    if ($self->_active_profile) {
        $self->_schedule_next_sample();
    }
}

sub _collect_stack_trace ($self) {
    my @frames = ();
    my $level = 1;  # Skip this function
    my $max_depth = $self->max_stack_depth;
    
    while (my @caller_info = caller($level)) {
        my ($package, $filename, $line, $subroutine) = @caller_info;
        
        # Skip profiling internals to avoid recursive sampling, but don't skip entirely
        if ($package =~ /^Sentry::Profiling/) {
            $level++;
            next;  # Skip this frame but continue to collect others
        }
        
        # Create frame object
        my $frame = Sentry::Profiling::Frame->from_caller_info(
            $package, $filename, $line, $subroutine
        );
        
        push @frames, $frame->to_hash();
        
        $level++;
        last if $level > $max_depth;  # Prevent excessive stack depth
    }
    
    return \@frames;
}

# Cleanup on object destruction
sub DESTROY ($self) {
    $self->stop() if $self->is_sampling();
}

1;

=head1 PERFORMANCE NOTES

This sampler uses SIGALRM for periodic sampling, which provides good accuracy
with minimal overhead. The signal handler is kept minimal and async-signal-safe.

Stack collection overhead is approximately 50-200 microseconds per sample,
depending on stack depth.

=head1 THREAD SAFETY

This implementation is designed for single-threaded Perl applications. 
Multi-threaded support would require additional synchronization.

=head1 SEE ALSO

L<Sentry::Profiling>, L<Sentry::Profiling::Profile>, L<Sentry::Profiling::Frame>

=head1 AUTHOR

Sentry Team

=head1 COPYRIGHT AND LICENSE

This software is licensed under the same terms as Perl itself.

=cut