package Sentry::Profiling::Profile;
use Mojo::Base -base, -signatures;

use Time::HiRes qw(time);
use Digest::SHA qw(sha256_hex);
use JSON::PP qw(encode_json);
use Config;

our $VERSION = '1.0.0';

# Profile metadata
has name => 'unnamed-profile';
has start_time => sub { time() };
has end_time => undef;
has transaction_id => undef;
has trace_id => undef;
has platform => 'perl';
has version => '1';
has environment => sub { $ENV{SENTRY_ENVIRONMENT} || 'production' };

# Profile data
has _samples => sub { [] };
has _frames => sub { {} };     # frame_id => frame_data
has _stacks => sub { {} };     # stack_signature => stack_data
has _frame_counter => 0;
has _stack_counter => 0;

=head1 NAME

Sentry::Profiling::Profile - Profile data structure for Sentry profiling

=head1 SYNOPSIS

    use Sentry::Profiling::Profile;
    
    my $profile = Sentry::Profiling::Profile->new(
        name => 'my-operation',
        transaction_id => 'txn-123',
        trace_id => 'trace-456',
    );
    
    # Add samples during profiling
    $profile->add_sample($sample_data);
    
    # Finish and convert to envelope format
    $profile->finish();
    my $envelope_item = $profile->to_envelope_item();

=head1 DESCRIPTION

This module represents a complete profiling session, storing stack samples
and managing frame deduplication for efficient transport to Sentry.

=head1 ATTRIBUTES

=head2 name

Profile name for identification.

=head2 start_time

When profiling started (Unix timestamp with fractional seconds).

=head2 end_time

When profiling ended (Unix timestamp with fractional seconds).

=head2 transaction_id

Associated transaction ID for correlation.

=head2 trace_id

Associated trace ID for distributed tracing correlation.

=head2 platform

Platform identifier ('perl').

=head2 version

Profile format version ('1').

=head2 environment

Environment name (from SENTRY_ENVIRONMENT or 'production').

=head1 METHODS

=head2 add_sample

    $profile->add_sample($sample);

Add a stack sample to the profile.

Sample format:
    {
        timestamp => 1692547200.123,
        thread_id => "12345",
        frames => [
            { function => 'main', filename => 'script.pl', ... },
            { function => 'process', filename => 'lib/App.pm', ... },
        ]
    }

=cut

sub add_sample ($self, $sample) {
    my $stack_id = $self->_get_or_create_stack($sample->{frames});
    
    push @{$self->_samples}, {
        stack_id => $stack_id,
        thread_id => $sample->{thread_id} || "0",
        elapsed_since_start_ns => int(($sample->{timestamp} - $self->start_time) * 1_000_000_000),
    };
}

=head2 finish

    $profile->finish();

Mark the profile as complete. Sets the end_time.

=cut

sub finish ($self) {
    $self->end_time(time()) unless $self->end_time;
}

=head2 to_envelope_item

    my $envelope_item = $profile->to_envelope_item();

Convert profile to Sentry envelope item format for transport.

=cut

sub to_envelope_item ($self) {
    # Ensure profile is finished
    $self->finish() unless $self->end_time;
    
    my $profile_data = {
        version => $self->version,
        platform => $self->platform,
        environment => $self->environment,
        timestamp => $self->start_time,
        duration_ns => int(($self->end_time - $self->start_time) * 1_000_000_000),
        
        samples => $self->_samples,
        stacks => $self->_get_stacks_array(),
        frames => $self->_get_frames_array(),
        
        # Runtime information
        runtime => {
            name => 'perl',
            version => $^V ? $^V->stringify : $],
        },
        
        # Device information
        device => {
            architecture => $Config::Config{archname} || 'unknown',
        },
        
        thread_metadata => {
            "$$" => { name => 'main' },
        },
    };
    
    my $envelope_item = {
        type => 'profile',
        profile => $profile_data,
    };
    
    # Add transaction correlation if available
    if ($self->transaction_id && $self->trace_id) {
        $envelope_item->{transaction} = {
            id => $self->transaction_id,
            trace_id => $self->trace_id,
            name => $self->name,
            active_thread_id => "$$",
        };
    }
    
    return $envelope_item;
}

=head2 get_stats

    my $stats = $profile->get_stats();

Get statistics about the profile.

=cut

sub get_stats ($self) {
    return {
        sample_count => scalar @{$self->_samples},
        unique_frames => scalar keys %{$self->_frames},
        unique_stacks => scalar keys %{$self->_stacks},
        duration => $self->end_time ? ($self->end_time - $self->start_time) : undef,
        name => $self->name,
    };
}

=head2 get_sample_count

    my $count = $profile->get_sample_count();

Get the number of samples in this profile.

=cut

sub get_sample_count ($self) {
    return scalar @{$self->_samples};
}

=head2 get_duration

    my $duration = $profile->get_duration();

Get profile duration in seconds (returns undef if not finished).

=cut

sub get_duration ($self) {
    return undef unless $self->end_time;
    return $self->end_time - $self->start_time;
}

# Internal methods

sub _get_or_create_stack ($self, $frames) {
    my @frame_ids = map { $self->_get_or_create_frame($_) } @$frames;
    my $stack_signature = join('|', @frame_ids);
    
    unless (exists $self->_stacks->{$stack_signature}) {
        my $current_count = $self->_stack_counter;
        $self->_stacks->{$stack_signature} = {
            stack_id => $current_count,
            frame_ids => \@frame_ids,
        };
        $self->_stack_counter($current_count + 1);
    }
    return $self->_stacks->{$stack_signature}->{stack_id};
}

sub _get_or_create_frame ($self, $frame_data) {
    # Create a signature for frame deduplication
    my $frame_signature = sprintf('%s:%s:%d:%s',
        $frame_data->{package} || '',
        $frame_data->{filename} || '',
        $frame_data->{lineno} || 0,
        $frame_data->{function} || ''
    );
    
    my $frame_id = sha256_hex($frame_signature);
    
    unless (exists $self->_frames->{$frame_id}) {
        my $current_count = $self->_frame_counter;
        $self->_frames->{$frame_id} = {
            frame_id => $current_count,
            function => $frame_data->{function} || '(unknown)',
            filename => $frame_data->{filename} || '(unknown)',
            lineno => $frame_data->{lineno} || 0,
            module => $frame_data->{module} || $frame_data->{package} || '(unknown)',
            in_app => $frame_data->{in_app} ? \1 : \0,  # JSON boolean
            package => $frame_data->{package} || '(unknown)',
        };
        $self->_frame_counter($current_count + 1);
    }
    return $frame_id;
}

sub _get_stacks_array ($self) {
    my @stacks = ();
    
    # Sort by stack_id for consistent output
    for my $signature (sort { 
        $self->_stacks->{$a}->{stack_id} <=> $self->_stacks->{$b}->{stack_id} 
    } keys %{$self->_stacks}) {
        my $stack_data = $self->_stacks->{$signature};
        
        # Convert frame IDs to frame indices
        my @frame_indices = map { 
            $self->_frames->{$_}->{frame_id} 
        } @{$stack_data->{frame_ids}};
        
        push @stacks, \@frame_indices;
    }
    
    return \@stacks;
}

sub _get_frames_array ($self) {
    my @frames = ();
    
    # Sort by frame_id for consistent output  
    for my $frame_id (sort { 
        $self->_frames->{$a}->{frame_id} <=> $self->_frames->{$b}->{frame_id} 
    } keys %{$self->_frames}) {
        my $frame = $self->_frames->{$frame_id};
        
        push @frames, {
            function => $frame->{function},
            filename => $frame->{filename},
            lineno => $frame->{lineno},
            module => $frame->{module},
            in_app => $frame->{in_app},
            package => $frame->{package},
        };
    }
    
    return \@frames;
}

1;

=head1 DATA STRUCTURE

The profile envelope follows Sentry's profiling format:

    {
        type => 'profile',
        profile => {
            version => '1',
            platform => 'perl',
            timestamp => 1692547200.123,
            duration_ns => 30000000000,
            samples => [
                {
                    stack_id => 0,
                    thread_id => "12345",
                    elapsed_since_start_ns => 1000000,
                },
                ...
            ],
            stacks => [
                [0, 1, 2],  # frame indices
                [0, 1, 3],
                ...
            ],
            frames => [
                {
                    function => 'main',
                    filename => 'script.pl',
                    lineno => 10,
                    module => 'main',
                    in_app => true,
                },
                ...
            ],
        }
    }

=head1 PERFORMANCE

Frame deduplication significantly reduces payload size for profiles with
repetitive call stacks. A typical web application might have 90%+ frame
reuse across samples.

=head1 SEE ALSO

L<Sentry::Profiling>, L<Sentry::Profiling::StackSampler>, L<Sentry::Profiling::Frame>

=head1 AUTHOR

Sentry Team

=head1 COPYRIGHT AND LICENSE

This software is licensed under the same terms as Perl itself.

=cut