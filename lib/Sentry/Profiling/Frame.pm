package Sentry::Profiling::Frame;
use Mojo::Base -base, -signatures;

use File::Spec;
use Cwd qw(getcwd);

our $VERSION = '1.0.0';

# Frame attributes
has package => undef;
has filename => undef; 
has lineno => undef;
has function => undef;
has in_app => undef;
has module => undef;

=head1 NAME

Sentry::Profiling::Frame - Stack frame representation for profiling

=head1 SYNOPSIS

    use Sentry::Profiling::Frame;
    
    # Create from caller info
    my $frame = Sentry::Profiling::Frame->from_caller_info(
        'MyApp::Service', '/path/to/file.pm', 42, 'MyApp::Service::process'
    );
    
    # Convert to hash for serialization
    my $hash = $frame->to_hash();

=head1 DESCRIPTION

Represents a single stack frame in a profiling sample. Handles the conversion
from Perl's caller() information to Sentry's frame format.

=head1 METHODS

=head2 from_caller_info

    my $frame = Sentry::Profiling::Frame->from_caller_info(
        $package, $filename, $line, $subroutine
    );

Create a frame from Perl's caller() information.

=cut

sub from_caller_info ($class, $package, $filename, $line, $subroutine) {
    my $self = $class->new();
    
    $self->package($package // '(unknown)');
    $self->filename($filename // '(unknown)');
    $self->lineno($line // 0);
    
    # Clean up function name
    my $function = $subroutine // '(main)';
    $function =~ s/^.*:://;  # Remove package prefix
    $function = '(main)' if $function eq '__ANON__';
    $self->function($function);
    
    # Set module (same as package for Perl)
    $self->module($package // '(unknown)');
    
    # Determine if this is application code
    $self->in_app($self->_determine_in_app($filename));
    
    return $self;
}

=head2 to_hash

    my $hash = $frame->to_hash();

Convert frame to hash representation compatible with Sentry's profiling format.

=cut

sub to_hash ($self) {
    return {
        function => $self->function,
        filename => $self->_normalize_filename($self->filename),
        lineno => $self->lineno,
        module => $self->module,
        in_app => $self->in_app ? \1 : \0,  # JSON boolean
        package => $self->package,
    };
}

=head2 signature

    my $sig = $frame->signature();

Generate a unique signature for this frame for deduplication purposes.

=cut

sub signature ($self) {
    return sprintf('%s:%s:%d:%s',
        $self->package // '',
        $self->filename // '',
        $self->lineno // 0,
        $self->function // ''
    );
}

# Internal methods

sub _determine_in_app ($self, $filename) {
    return 0 unless defined $filename;
    
    # System/library paths are not in_app
    return 0 if $filename =~ m{^/usr/};
    return 0 if $filename =~ m{/perl5/};
    return 0 if $filename =~ m{/site_perl/};
    return 0 if $filename =~ m{/vendor_perl/};
    
    # CPAN modules are not in_app
    return 0 if $filename =~ m{/lib/perl/};
    return 0 if $filename =~ m{\.cpan/};
    
    # Files in current working directory or subdirectories are in_app
    my $cwd = eval { getcwd() };
    if ($cwd && $filename =~ /^\Q$cwd\E/) {
        return 1;
    }
    
    # Relative paths are likely in_app
    return 1 unless File::Spec->file_name_is_absolute($filename);
    
    # Conservative default
    return 0;
}

sub _normalize_filename ($self, $filename) {
    return $filename unless defined $filename;
    
    # Try to make paths relative to current directory for cleaner display
    my $cwd = eval { getcwd() };
    if ($cwd && $filename =~ /^\Q$cwd\E\/(.+)$/) {
        return $1;
    }
    
    return $filename;
}

1;

=head1 FRAME FORMAT

The frame hash format matches Sentry's profiling expectations:

    {
        function => 'method_name',
        filename => 'relative/path/to/file.pm',
        lineno => 42,
        module => 'Package::Name',
        in_app => true,
        package => 'Package::Name',
    }

=head1 IN_APP DETECTION

Frames are marked as "in_app" (application code) vs library code using heuristics:

- Files in system paths (/usr/, perl5/, etc.) are library code
- Files in the current working directory are application code  
- CPAN module paths are library code
- Relative paths are assumed to be application code

=head1 SEE ALSO

L<Sentry::Profiling>, L<Sentry::Profiling::Profile>, L<Sentry::Profiling::StackSampler>

=head1 AUTHOR

Sentry Team

=head1 COPYRIGHT AND LICENSE

This software is licensed under the same terms as Perl itself.

=cut