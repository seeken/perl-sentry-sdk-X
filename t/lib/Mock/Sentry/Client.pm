package Mock::Sentry::Client;
use Mojo::Base -base, -signatures;

# has [qw(capture_message capture_event capture_exception)];
has [qw(_captured_message)];
has 'envelopes' => sub { [] };

sub capture_message (
  $self, $message,
  $level = undef,
  $hint  = undef,
  $scope = undef
) {
  $self->_captured_message(
    { message => $message, level => $level, hint => $hint, scope => $scope });
}

sub capture_event ($self, $event, $hint = undef, $scope = undef) {
  $self->_captured_message({ event => $event, hint => $hint, scope => $scope });
}

# Mock envelope methods for structured logging
sub _prepare_envelope ($self) {
  require Mock::Sentry::Envelope;
  return Mock::Sentry::Envelope->new();
}

sub _send_envelope ($self, $envelope) {
  push @{$self->envelopes}, $envelope;
  return 1;  # Success
}

sub clear_envelopes ($self) {
  $self->envelopes([]);
  return $self;
}

sub capture_exception ($self, $exception, $hint = undef, $scope = undef) {
  $self->_captured_message({
    exception => $exception, hint => $hint, scope => $scope });
}

1;
