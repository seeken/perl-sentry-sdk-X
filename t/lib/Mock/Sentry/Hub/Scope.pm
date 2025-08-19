package Mock::Sentry::Hub::Scope;
use Mojo::Base -base, -signatures;

has transaction => undef;
has user => sub { {} };
has tags => sub { {} };
has extra => sub { {} };
has span => undef;

sub get_transaction ($self) {
    return $self->transaction;
}

1;
