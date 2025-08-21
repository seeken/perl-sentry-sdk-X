package Sentry::Profiling::Utils;
use Mojo::Base -base, -signatures;

use Time::HiRes qw(time);
use File::Spec;

our $VERSION = '1.0.0';

=head1 NAME

Sentry::Profiling::Utils - Utility functions for Sentry profiling

=head1 SYNOPSIS

    use Sentry::Profiling::Utils;
    
    my $utils = Sentry::Profiling::Utils->new();
    
    # System monitoring
    my $cpu = $utils->get_cpu_usage();
    my $memory = $utils->get_memory_usage_mb();
    
    # Performance measurement
    my ($result, $duration) = $utils->time_execution(sub {
        expensive_operation();
    });

=head1 DESCRIPTION

This module provides utility functions for profiling operations including
system monitoring, performance measurement, and frame filtering.

=head1 METHODS

=head2 get_cpu_usage

    my $cpu_percent = $utils->get_cpu_usage();

Get current CPU usage percentage (0-100). Returns 0 if unable to determine.

=cut

sub get_cpu_usage ($self) {
    # Simple implementation using /proc/loadavg on Linux
    if (-r '/proc/loadavg') {
        eval {
            open my $fh, '<', '/proc/loadavg' or return 0;
            my $line = <$fh>;
            close $fh;
            
            if ($line && $line =~ /^(\d+\.\d+)/) {
                # Load average as rough CPU percentage (capped at 100%)
                return $1 > 1.0 ? 100 : int($1 * 100);
            }
        };
    }
    
    return 0;  # Unable to determine
}

=head2 get_memory_usage_mb

    my $memory_mb = $utils->get_memory_usage_mb();

Get current process memory usage in MB. Returns 0 if unable to determine.

=cut

sub get_memory_usage_mb ($self) {
    # Try reading from /proc/self/status on Linux
    if (-r '/proc/self/status') {
        eval {
            open my $fh, '<', '/proc/self/status' or return 0;
            while (my $line = <$fh>) {
                if ($line =~ /^VmRSS:\s+(\d+)\s+kB/) {
                    close $fh;
                    return int($1 / 1024);  # Convert KB to MB
                }
            }
            close $fh;
        };
    }
    
    # Fallback: estimate from process info if available
    eval {
        if (open my $fh, '-|', 'ps -o rss= -p $$') {
            my $rss_kb = <$fh>;
            close $fh;
            if ($rss_kb && $rss_kb =~ /^\s*(\d+)/) {
                return int($1 / 1024);  # Convert KB to MB
            }
        }
    };
    
    return 0;  # Unable to determine
}

=head2 time_execution

    my ($result, $duration_seconds) = $utils->time_execution($coderef);

Execute code and measure execution time, returning both result and duration.

=cut

sub time_execution ($self, $coderef) {
    my $start_time = time();
    my @result;
    my $wantarray = wantarray;
    
    eval {
        if ($wantarray) {
            @result = $coderef->();
        } elsif (defined $wantarray) {
            $result[0] = $coderef->();
        } else {
            $coderef->();
        }
    };
    
    my $duration = time() - $start_time;
    my $error = $@;
    
    die $error if $error;
    
    return $wantarray ? (\@result, $duration) : ($result[0], $duration);
}

=head2 is_system_package

    my $is_system = $utils->is_system_package($package_name);

Check if a package is a system/library package (not application code).

=cut

sub is_system_package ($self, $package_name) {
    return 1 unless defined $package_name;
    
    # Common system packages
    return 1 if $package_name =~ /^(strict|warnings|base|parent|Exporter)$/;
    return 1 if $package_name =~ /^(Carp|Data::Dumper|Scalar::Util)$/;
    return 1 if $package_name =~ /^(Test::|Test2::)/;
    return 1 if $package_name =~ /^(Mojo::|Mojolicious::)/;
    return 1 if $package_name =~ /^(DBI|DBD::)/;
    return 1 if $package_name =~ /^(LWP::|HTTP::)/;
    return 1 if $package_name =~ /^(JSON::|XML::)/;
    return 1 if $package_name =~ /^(YAML::|MIME::)/;
    return 1 if $package_name =~ /^(Digest::|Compress::)/;
    return 1 if $package_name =~ /^(File::|Path::)/;
    return 1 if $package_name =~ /^(Time::|DateTime)/;
    
    return 0;
}

=head2 normalize_frame_filename

    my $normalized = $utils->normalize_frame_filename($filename);

Normalize a frame filename for consistent display and grouping.

=cut

sub normalize_frame_filename ($self, $filename) {
    return '(unknown)' unless defined $filename && length $filename;
    
    # Convert to forward slashes for consistency
    $filename =~ s{\\}{/}g;
    
    # Try to make relative to current directory
    my $cwd = eval { Cwd::getcwd() } || '';
    if ($cwd && $filename =~ /^\Q$cwd\E\/(.+)$/) {
        return $1;
    }
    
    # Shorten common system paths
    $filename =~ s{^/usr/local/lib/perl5/[^/]+/[^/]+/}{\@perl/};
    $filename =~ s{^/usr/lib/perl5/[^/]+/[^/]+/}{\@perl/};
    $filename =~ s{^/usr/share/perl5/}{\@perl/};
    
    return $filename;
}

=head2 filter_stack_frames

    my $filtered_frames = $utils->filter_stack_frames($frames, $config);

Filter stack frames based on configuration rules.

=cut

sub filter_stack_frames ($self, $frames, $config) {
    return [] unless $frames && @$frames;
    
    my @filtered;
    my $max_frames = $config->max_frames_per_sample;
    
    for my $frame (@$frames) {
        last if @filtered >= $max_frames;
        
        my $package = $frame->{package} || '';
        
        # Skip if package should be ignored
        next if $config->should_ignore_package($package);
        
        # Skip system packages unless explicitly included
        next if $self->is_system_package($package) && !$config->should_ignore_package($package);
        
        push @filtered, $frame;
    }
    
    return \@filtered;
}

=head2 estimate_profile_overhead

    my $overhead_percent = $utils->estimate_profile_overhead($sample_count, $duration);

Estimate the CPU overhead of profiling based on sample count and duration.

=cut

sub estimate_profile_overhead ($self, $sample_count, $duration) {
    return 0 unless $sample_count && $duration;
    
    # Rough estimation: each sample takes ~100 microseconds
    my $sampling_time = $sample_count * 0.0001;  # 100 microseconds per sample
    my $overhead_percent = ($sampling_time / $duration) * 100;
    
    # Cap at 100%
    return $overhead_percent > 100 ? 100 : $overhead_percent;
}

=head2 should_throttle_sampling

    my $throttle = $utils->should_throttle_sampling($cpu_usage, $memory_usage, $config);

Determine if sampling should be throttled based on system load.

=cut

sub should_throttle_sampling ($self, $cpu_usage, $memory_usage, $config) {
    return 0 unless $config->adaptive_sampling;
    
    # Throttle if CPU usage is too high
    return 1 if $cpu_usage > $config->cpu_threshold_percent;
    
    # Throttle if memory usage is too high
    return 1 if $memory_usage > $config->memory_threshold_mb;
    
    return 0;
}

=head2 create_profile_metadata

    my $metadata = $utils->create_profile_metadata($profile, $config);

Create metadata for a profile.

=cut

sub create_profile_metadata ($self, $profile, $config) {
    my $stats = $profile->get_stats();
    
    return {
        profiler_version => $VERSION,
        sampling_interval_us => $config->sampling_interval_us,
        max_stack_depth => $config->max_stack_depth,
        sample_count => $stats->{sample_count},
        unique_frames => $stats->{unique_frames},
        unique_stacks => $stats->{unique_stacks},
        duration_seconds => $stats->{duration},
        estimated_overhead_percent => $self->estimate_profile_overhead(
            $stats->{sample_count}, 
            $stats->{duration}
        ),
    };
}

1;

=head1 SYSTEM MONITORING

The utility functions attempt to monitor system resources using:

=over 4

=item * /proc/loadavg for CPU load estimation

=item * /proc/self/status for memory usage (RSS)

=item * ps command as fallback for memory

=back

These methods are Linux-centric but degrade gracefully on other systems.

=head1 PERFORMANCE ESTIMATION

The overhead estimation is based on empirical measurements of stack sampling
performance, typically around 100 microseconds per sample on modern systems.

=head1 SEE ALSO

L<Sentry::Profiling>, L<Sentry::Profiling::Config>, L<Sentry::Profiling::StackSampler>

=head1 AUTHOR

Sentry Team

=head1 COPYRIGHT AND LICENSE

This software is licensed under the same terms as Perl itself.

=cut