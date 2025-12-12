package Mock::Sentry::Envelope;
use Mojo::Base -base, -signatures;

has 'items' => sub { [] };

sub add_item ($self, $type, $data, $headers = {}) {
    push @{$self->items}, { type => $type, data => $data, headers => $headers };
    return $self;
}

1;
