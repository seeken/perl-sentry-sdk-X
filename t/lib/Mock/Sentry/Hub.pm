package Mock::Sentry::Hub;
use Mojo::Base -base, -signatures;

has captured_events => sub { [] };
has client => undef;
has scope => sub { 
    require Mock::Sentry::Hub::Scope;
    Mock::Sentry::Hub::Scope->new();
};

sub capture_event ($self, $transaction) {
  push $self->captured_events->@*, $transaction;
}

1;
