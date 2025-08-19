package Mock::Sentry::Envelope;
use Mojo::Base -base, -signatures;

has 'items' => sub { [] };

sub add_item ($self, $type, $data) {
    push @{$self->items}, { type => $type, data => $data };
    return $self;
}

1;
