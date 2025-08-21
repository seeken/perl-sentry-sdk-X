package Sentry::Profiling::Config;
use Mojo::Base -base, -signatures;

our $VERSION = '1.0.0';

# Default configuration values
use constant DEFAULT_PROFILES_SAMPLE_RATE => 0.01;
use constant DEFAULT_PROFILE_SESSION_SAMPLE_RATE => 1.0;
use constant DEFAULT_SAMPLING_INTERVAL_US => 10_000;  # 10ms
use constant DEFAULT_MAX_PROFILE_DURATION => 30;      # 30 seconds
use constant DEFAULT_MAX_STACK_DEPTH => 100;
use constant DEFAULT_PROFILE_LIFECYCLE => 'trace';

# Configuration attributes
has enable_profiling => 0;
has profiles_sample_rate => DEFAULT_PROFILES_SAMPLE_RATE;
has profile_session_sample_rate => DEFAULT_PROFILE_SESSION_SAMPLE_RATE;
has sampling_interval_us => DEFAULT_SAMPLING_INTERVAL_US;
has max_profile_duration => DEFAULT_MAX_PROFILE_DURATION;
has max_stack_depth => DEFAULT_MAX_STACK_DEPTH;
has profile_lifecycle => DEFAULT_PROFILE_LIFECYCLE;

# Advanced configuration
has min_sampling_interval_us => 1_000;   # 1ms minimum
has max_sampling_interval_us => 1_000_000; # 1s maximum
has adaptive_sampling => 0;               # Adaptive sampling based on load
has cpu_threshold_percent => 80;          # CPU threshold for adaptive sampling
has memory_threshold_mb => 100;           # Memory threshold

# Profile filtering
has ignore_packages => sub { [] };        # Packages to ignore in profiles
has include_packages => sub { [] };       # Only include these packages
has max_frames_per_sample => 200;         # Maximum frames per sample

=head1 NAME

Sentry::Profiling::Config - Configuration management for Sentry profiling

=head1 SYNOPSIS

    use Sentry::Profiling::Config;
    
    my $config = Sentry::Profiling::Config->new(
        enable_profiling => 1,
        profiles_sample_rate => 0.1,
        adaptive_sampling => 1,
    );
    
    # Validate configuration
    my $errors = $config->validate();
    die "Config errors: " . join(', ', @$errors) if @$errors;

=head1 DESCRIPTION

This module manages configuration for Sentry profiling, providing validation,
defaults, and advanced configuration options.

=head1 METHODS

=head2 validate

    my $errors = $config->validate();

Validate the configuration and return an array reference of error messages.

=cut

sub validate ($self) {
    my @errors;
    
    # Validate sample rates
    if ($self->profiles_sample_rate < 0 || $self->profiles_sample_rate > 1) {
        push @errors, "profiles_sample_rate must be between 0 and 1";
    }
    
    if ($self->profile_session_sample_rate < 0 || $self->profile_session_sample_rate > 1) {
        push @errors, "profile_session_sample_rate must be between 0 and 1";
    }
    
    # Validate sampling interval
    if ($self->sampling_interval_us < $self->min_sampling_interval_us) {
        push @errors, sprintf("sampling_interval_us must be at least %d microseconds",
            $self->min_sampling_interval_us);
    }
    
    if ($self->sampling_interval_us > $self->max_sampling_interval_us) {
        push @errors, sprintf("sampling_interval_us must be at most %d microseconds",
            $self->max_sampling_interval_us);
    }
    
    # Validate duration and stack depth
    if ($self->max_profile_duration <= 0) {
        push @errors, "max_profile_duration must be positive";
    }
    
    if ($self->max_stack_depth <= 0) {
        push @errors, "max_stack_depth must be positive";
    }
    
    # Validate lifecycle
    unless ($self->profile_lifecycle =~ /^(trace|manual)$/) {
        push @errors, "profile_lifecycle must be 'trace' or 'manual'";
    }
    
    # Validate thresholds
    if ($self->cpu_threshold_percent < 1 || $self->cpu_threshold_percent > 100) {
        push @errors, "cpu_threshold_percent must be between 1 and 100";
    }
    
    if ($self->memory_threshold_mb <= 0) {
        push @errors, "memory_threshold_mb must be positive";
    }
    
    return \@errors;
}

=head2 from_options

    my $config = Sentry::Profiling::Config->from_options($options);

Create a configuration object from SDK options hash.

=cut

sub from_options ($class, $options = {}) {
    my $config = $class->new();
    
    # Basic profiling options
    $config->enable_profiling($options->{enable_profiling} // 0);
    $config->profiles_sample_rate($options->{profiles_sample_rate} // DEFAULT_PROFILES_SAMPLE_RATE);
    $config->profile_session_sample_rate($options->{profile_session_sample_rate} // DEFAULT_PROFILE_SESSION_SAMPLE_RATE);
    $config->sampling_interval_us($options->{sampling_interval_us} // DEFAULT_SAMPLING_INTERVAL_US);
    $config->max_profile_duration($options->{max_profile_duration} // DEFAULT_MAX_PROFILE_DURATION);
    $config->max_stack_depth($options->{max_stack_depth} // DEFAULT_MAX_STACK_DEPTH);
    $config->profile_lifecycle($options->{profile_lifecycle} // DEFAULT_PROFILE_LIFECYCLE);
    
    # Advanced options
    $config->adaptive_sampling($options->{adaptive_sampling} // 0);
    $config->cpu_threshold_percent($options->{cpu_threshold_percent} // 80);
    $config->memory_threshold_mb($options->{memory_threshold_mb} // 100);
    $config->max_frames_per_sample($options->{max_frames_per_sample} // 200);
    
    # Package filtering
    if ($options->{ignore_packages}) {
        $config->ignore_packages([
            ref($options->{ignore_packages}) eq 'ARRAY' 
                ? @{$options->{ignore_packages}}
                : ($options->{ignore_packages})
        ]);
    }
    
    if ($options->{include_packages}) {
        $config->include_packages([
            ref($options->{include_packages}) eq 'ARRAY'
                ? @{$options->{include_packages}}
                : ($options->{include_packages})
        ]);
    }
    
    return $config;
}

=head2 should_ignore_package

    my $ignore = $config->should_ignore_package($package_name);

Check if a package should be ignored in profiling.

=cut

sub should_ignore_package ($self, $package_name) {
    # If include_packages is specified, only include those
    if (@{$self->include_packages}) {
        return !grep { $package_name =~ /^\Q$_\E/ } @{$self->include_packages};
    }
    
    # Otherwise, check ignore list
    return grep { $package_name =~ /^\Q$_\E/ } @{$self->ignore_packages};
}

=head2 get_effective_sampling_interval

    my $interval = $config->get_effective_sampling_interval($cpu_usage, $memory_usage);

Get the effective sampling interval, potentially adjusted for adaptive sampling.

=cut

sub get_effective_sampling_interval ($self, $cpu_usage = 0, $memory_usage = 0) {
    return $self->sampling_interval_us unless $self->adaptive_sampling;
    
    my $base_interval = $self->sampling_interval_us;
    my $multiplier = 1.0;
    
    # Increase interval if CPU usage is high
    if ($cpu_usage > $self->cpu_threshold_percent) {
        $multiplier *= (1 + ($cpu_usage - $self->cpu_threshold_percent) / 100);
    }
    
    # Increase interval if memory usage is high
    if ($memory_usage > $self->memory_threshold_mb) {
        $multiplier *= (1 + ($memory_usage - $self->memory_threshold_mb) / 100);
    }
    
    my $adjusted_interval = int($base_interval * $multiplier);
    
    # Clamp to limits
    $adjusted_interval = $self->min_sampling_interval_us if $adjusted_interval < $self->min_sampling_interval_us;
    $adjusted_interval = $self->max_sampling_interval_us if $adjusted_interval > $self->max_sampling_interval_us;
    
    return $adjusted_interval;
}

1;

=head1 CONFIGURATION OPTIONS

=head2 Basic Options

=over 4

=item enable_profiling

Boolean flag to enable/disable profiling.

=item profiles_sample_rate

Percentage of profiles to sample (0.0 to 1.0).

=item profile_session_sample_rate  

Percentage of sessions eligible for profiling (0.0 to 1.0).

=item sampling_interval_us

Sampling interval in microseconds.

=item max_profile_duration

Maximum profile duration in seconds.

=item max_stack_depth

Maximum stack depth to capture.

=item profile_lifecycle

When to profile: 'trace' (automatic with transactions) or 'manual'.

=back

=head2 Advanced Options

=over 4

=item adaptive_sampling

Enable adaptive sampling based on system load.

=item cpu_threshold_percent

CPU usage threshold for adaptive sampling.

=item memory_threshold_mb

Memory usage threshold for adaptive sampling.

=item ignore_packages

Array of package patterns to ignore in profiles.

=item include_packages

Array of package patterns to include (exclusive).

=item max_frames_per_sample

Maximum frames to collect per sample.

=back

=head1 SEE ALSO

L<Sentry::Profiling>, L<Sentry::Profiling::StackSampler>

=head1 AUTHOR

Sentry Team

=head1 COPYRIGHT AND LICENSE

This software is licensed under the same terms as Perl itself.

=cut