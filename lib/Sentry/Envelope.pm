package Sentry::Envelope;
use Mojo::Base -base, -signatures;

use Mojo::JSON qw(encode_json);

has event_id     => undef;
has headers      => sub ($self) { { event_id => $self->event_id } };
has items        => sub { [] };  # Array of envelope items

# Backward compatibility properties
has body         => sub { {} };
has sample_rates => sub { [{ id => "client_rate", rate => "1" }] };    # FIXME
has type         => 'transaction';
has item_headers =>
  sub ($self) { { type => $self->type, sample_rates => $self->sample_rates } };

sub add_item ($self, $type, $data, $headers = {}) {
  push $self->items->@*, {
    headers => { type => $type, %$headers },
    payload => $data
  };
  return $self;
}

sub get_items ($self) {
  return $self->items->@*;
}

sub serialize ($self) {
  my @lines = (encode_json($self->headers));
  
  # Handle new multi-item format
  if (@{$self->items}) {
    for my $item ($self->items->@*) {
      push @lines, encode_json($item->{headers});
      push @lines, ref($item->{payload}) ? encode_json($item->{payload}) : $item->{payload};
    }
  } else {
    # Backward compatibility: old single-item format
    push @lines, encode_json($self->item_headers);
    push @lines, encode_json($self->body);
  }
  
  return join("\n", @lines);
}

1;
