package Sentry::Integration::DieHandler;
use Mojo::Base 'Sentry::Integration::Base', -signatures;

use Mojo::Exception;

sub setup_once ($self, $add_global_event_processor, $get_current_hub) {
  ## no critic (Variables::RequireLocalizedPunctuationVars)
  $SIG{__DIE__} = sub {
    my $error = shift;

    # Don't interfere with exception objects that already have stack traces
    if (ref $error && $error->can('frames') && @{$error->frames // []}) {
      # If we're NOT in an eval, capture to Sentry before dying
      unless ($^S) {
        my $hub = $get_current_hub->();
        $hub->capture_exception($error) if $hub;
      }
      CORE::die $error;
    }

    # Create Mojo::Exception with trace NOW (at the point of die)
    # This captures the actual call stack where the error occurred
    # Skip 2 frames: this anonymous sub and the __DIE__ signal handler itself
    my $exception = Mojo::Exception->new($error)->trace(2);

    # If we're NOT in an eval, capture to Sentry before dying
    # (fatal error that will terminate the program)
    unless ($^S) {
      my $hub = $get_current_hub->();
      $hub->capture_exception($exception) if $hub;
    }

    # Re-throw with the trace attached
    # This ensures that even if caught by eval/try, the exception
    # object preserves the original stack trace
    CORE::die $exception;
  };
}

1;
