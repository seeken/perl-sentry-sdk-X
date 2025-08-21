package Sentry::Profiling;
use Mojo::Base -base, -signatures;

use Time::HiRes qw(time);
use Sentry::Profiling::Profile;
use Sentry::Profiling::StackSampler;
use Sentry::Profiling::Config;
use Sentry::Logger;

our $VERSION = '1.0.0';

# Configuration - use Config object
has config => sub { Sentry::Profiling::Config->new() };

# Backward compatibility properties
has enable_profiling => sub ($self) { $self->config->enable_profiling };
has profiles_sample_rate => sub ($self) { $self->config->profiles_sample_rate };
has profile_session_sample_rate => sub ($self) { $self->config->profile_session_sample_rate };
has profile_lifecycle => sub ($self) { $self->config->profile_lifecycle };
has sampling_interval_us => sub ($self) { $self->config->sampling_interval_us };
has max_profile_duration => sub ($self) { $self->config->max_profile_duration };
has max_stack_depth => sub ($self) { $self->config->max_stack_depth };

# Internal state
has _active_profile => undef;
has _sampler => sub { 
    Sentry::Profiling::StackSampler->new(
        max_stack_depth => shift->max_stack_depth
    )
};
has _session_sampled => undef;
has _logger => sub { Sentry::Logger->new(component => 'Profiling') };

=head1 NAME

Sentry::Profiling - Continuous profiling support for Sentry Perl SDK

=head1 SYNOPSIS

    use Sentry::Profiling;
    
    my $profiler = Sentry::Profiling->new(
        enable_profiling => 1,
        profiles_sample_rate => 0.1,
    );
    
    # Start profiling
    my $profile = $profiler->start_profiler({ name => 'my-operation' });
    
    # Do some work
    expensive_computation();
    
    # Stop and send profile
    $profiler->stop_profiler();

=head1 DESCRIPTION

This module provides continuous profiling capabilities for the Sentry Perl SDK.
It samples application call stacks during execution to provide performance insights.

=head1 ATTRIBUTES

=head2 enable_profiling

Boolean flag to enable/disable profiling. Default: false.

=head2 profiles_sample_rate

Percentage of profiles to sample (0.0 to 1.0). Default: 0.01 (1%).

=head2 profile_session_sample_rate

Percentage of sessions eligible for profiling (0.0 to 1.0). Default: 1.0 (100%).

=head2 profile_lifecycle

When to profile: 'trace' (automatic with transactions) or 'manual'. Default: 'trace'.

=head2 sampling_interval_us

Sampling interval in microseconds. Default: 10,000 (10ms).

=head2 max_profile_duration

Maximum profile duration in seconds. Default: 30.

=head2 max_stack_depth

Maximum stack depth to capture. Default: 100.

=head1 METHODS

=head2 start_profiler

    my $profile = $profiler->start_profiler($options);

Start profiling with optional parameters:

    $options = {
        name => 'profile-name',
        transaction_id => 'txn-id',
        trace_id => 'trace-id',
    }

Returns a L<Sentry::Profiling::Profile> object or undef if profiling is disabled
or sampling decides not to profile.

=cut

sub start_profiler ($self, $options = {}) {
    return undef unless $self->_should_start_profile($options);
    
    my $profile = Sentry::Profiling::Profile->new(
        start_time => time(),
        name => $options->{name} // 'manual-profile',
        transaction_id => $options->{transaction_id},
        trace_id => $options->{trace_id},
    );
    
    $self->_active_profile($profile);
    
    eval {
        $self->_sampler->start($profile, $self->sampling_interval_us);
        $self->_logger->debug("Started profiler", {
            profile_name => $profile->name,
            sampling_interval_us => $self->sampling_interval_us,
        });
    };
    
    if ($@) {
        $self->_logger->error("Failed to start profiler: $@");
        $self->_active_profile(undef);
        return undef;
    }
    
    return $profile;
}

=head2 stop_profiler

    my $profile = $profiler->stop_profiler();

Stop the current profiling session and send the profile to Sentry.
Returns the completed profile or undef if no active profile.

=cut

sub stop_profiler ($self) {
    my $profile = $self->_active_profile;
    return undef unless $profile;
    
    eval {
        $self->_sampler->stop();
        $profile->finish();
        $self->_active_profile(undef);
        
        $self->_logger->debug("Stopped profiler", {
            profile_name => $profile->name,
            sample_count => scalar @{$profile->_samples},
            duration => $profile->end_time - $profile->start_time,
        });
        
        # Send profile to Sentry
        $self->_send_profile($profile);
        
    };
    
    if ($@) {
        $self->_logger->error("Failed to stop profiler: $@");
        $self->_active_profile(undef);
    }
    
    return $profile;
}

=head2 start_transaction_profiling

    my $profile = $profiler->start_transaction_profiling($transaction);

Start profiling for a transaction. Used internally by the transaction system
when profile_lifecycle is set to 'trace'.

=cut

sub start_transaction_profiling ($self, $transaction) {
    return unless $self->profile_lifecycle eq 'trace';
    return unless $self->_should_profile_transaction($transaction);
    
    return $self->start_profiler({
        name => $transaction->name,
        transaction_id => $transaction->span_id,
        trace_id => $transaction->trace_id,
    });
}

=head2 is_profiling_active

    my $active = $profiler->is_profiling_active();

Check if profiling is currently active.

=cut

sub is_profiling_active ($self) {
    return defined $self->_active_profile;
}

=head2 get_active_profile

    my $profile = $profiler->get_active_profile();

Get the currently active profile, if any.

=cut

sub get_active_profile ($self) {
    return $self->_active_profile;
}

# Internal methods

sub _should_start_profile ($self, $options = {}) {
    return 0 unless $self->enable_profiling;
    return 0 if $self->_active_profile;  # Only one profile at a time
    
    # Session-level sampling
    if (!defined $self->_session_sampled) {
        $self->_session_sampled(rand() < $self->profile_session_sample_rate);
        $self->_logger->debug("Session profiling decision", {
            sampled => $self->_session_sampled,
            sample_rate => $self->profile_session_sample_rate,
        });
    }
    return 0 unless $self->_session_sampled;
    
    # Profile-level sampling
    my $should_sample = rand() < $self->profiles_sample_rate;
    $self->_logger->debug("Profile sampling decision", {
        should_sample => $should_sample,
        sample_rate => $self->profiles_sample_rate,
    });
    
    return $should_sample;
}

sub _should_profile_transaction ($self, $transaction) {
    return 0 unless $transaction->sampled;
    return $self->_should_start_profile();
}

sub _send_profile ($self, $profile) {
    eval {
        my $envelope_item = $profile->to_envelope_item();
        
        # Send via transport
        if (my $hub = Sentry::Hub->get_current_hub()) {
            my $client = $hub->client;
            if ($client && $client->can('send_envelope')) {
                $client->send_envelope($envelope_item);
                $self->_logger->info("Profile sent to Sentry", {
                    profile_name => $profile->name,
                    samples => scalar @{$profile->_samples},
                    frames => scalar keys %{$profile->_frames},
                });
            } else {
                $self->_logger->warn("No client available to send profile");
            }
        } else {
            $self->_logger->warn("No hub available to send profile");
        }
    };
    
    if ($@) {
        $self->_logger->error("Failed to send profile: $@");
    }
}

1;

=head1 SEE ALSO

L<Sentry::SDK>, L<Sentry::Profiling::Profile>, L<Sentry::Profiling::StackSampler>

=head1 AUTHOR

Sentry Team

=head1 COPYRIGHT AND LICENSE

This software is licensed under the same terms as Perl itself.

=cut