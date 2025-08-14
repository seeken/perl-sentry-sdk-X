package Mock::LWP::UserAgent;
use Mojo::Base 'LWP::UserAgent', -signatures;

use HTTP::Response;
use HTTP::Status ':constants';

has next_status_code => HTTP_OK;
has last_request => undef;

sub new {
  return Mojo::Base::new(@_);
}

sub request ($self, $request, @args) {
  $self->last_request($request);
  return HTTP::Response->new($self->next_status_code);
}

1;
