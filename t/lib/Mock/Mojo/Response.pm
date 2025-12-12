package Mock::Mojo::Response;
use Mojo::Base -base, -signatures;

has code     => 200;
has is_error => 0;
has json     => sub { {} };
has body     => '';
has error    => undef;
has headers  => sub { Mock::Mojo::Headers->new };

package Mock::Mojo::Headers;
use Mojo::Base -base, -signatures;

has _headers => sub { {} };

sub names ($self) {
    return [keys %{$self->_headers}];
}

sub header ($self, $name) {
    return $self->_headers->{lc($name)};
}

sub to_hash ($self) {
    return $self->_headers;
}

1;
