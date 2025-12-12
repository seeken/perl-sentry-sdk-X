package Sentry::Stacktrace;
use Mojo::Base -base, -signatures;

use Sentry::Stacktrace::Frame;

has exception => undef;

has frame_filter => sub {
  sub {0}
};

# In-app detection options (passed to Frame objects)
has in_app_include => sub { [] };
has in_app_exclude => sub { [] };

has frames => sub ($self) { return $self->prepare_frames() };

sub prepare_frames ($self) {
  if (!$self->exception->can('frames')) {
    return [];
  }

  my @frames = reverse map {
    my $frame = Sentry::Stacktrace::Frame->from_caller($_->@*);
    # Pass in-app detection options to the frame
    $frame->in_app_include($self->in_app_include);
    $frame->in_app_exclude($self->in_app_exclude);
    $frame;
  } $self->exception->frames->@*;

  return [grep { $self->frame_filter->($_) } @frames];
}

sub TO_JSON ($self) {
  return { frames => $self->frames };
}

1;
