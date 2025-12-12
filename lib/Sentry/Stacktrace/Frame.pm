package Sentry::Stacktrace::Frame;
use Mojo::Base -base, -signatures;

use Config qw(%Config);
use Mojo::File;
use Mojo::Home;
use Sentry::SourceFileRegistry;

has [qw(module filename line subroutine)];
has _source_file_registry => sub { Sentry::SourceFileRegistry->new };
has _home                 => sub { Mojo::Home->new->detect };

# In-app detection configuration (set from Client options)
has in_app_include => sub { [] };  # Module prefixes that ARE app code (takes precedence)
has in_app_exclude => sub { [] };  # Module prefixes that are NOT app code

sub _is_in_app ($self) {
  my $module = $self->module // '';
  my $filename = $self->filename // '';

  # in_app_include takes precedence - if module matches, it's in-app
  for my $prefix (@{$self->in_app_include // []}) {
    return 1 if $prefix && index($module, $prefix) == 0;
  }

  # in_app_exclude - if module matches, it's NOT in-app
  for my $prefix (@{$self->in_app_exclude // []}) {
    return 0 if $prefix && index($module, $prefix) == 0;
  }

  # Fall back to default heuristics:
  # - Relative paths (not starting with /) are likely app code
  # - Files not in Perl's siteprefix (CPAN) AND in the app's home are in-app
  return substr($filename, 0, 1) ne '/'
    || ( index($filename, $Config{siteprefix}) == -1
      && index($filename, $self->_home) > -1);
}

sub _map_file_to_context ($self) {
  return $self->_source_file_registry->get_context_lines($self->filename,
    $self->line);
}

sub _relative_filename ($self) {
  return Mojo::File::path($self->filename)->to_rel($self->_home)->to_string;
}

sub TO_JSON ($self) {
  return {
    in_app    => \($self->_is_in_app()),
    abs_path  => $self->filename,
    file_name => $self->_relative_filename,
    lineno    => $self->line,
    module    => $self->module,
    function  => $self->subroutine,
    %{ $self->_map_file_to_context() },
  };
}

sub from_caller ($package, $module, $filename, $line, $subroutine, @args) {
  return $package->new({
    module     => $module,
    filename   => $filename,
    line       => $line,
    subroutine => $subroutine
  });
}

1;
