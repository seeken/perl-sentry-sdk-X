package Sentry::Integration::DieHandler;
use Mojo::Base 'Sentry::Integration::Base', -signatures;

use Mojo::Exception;

sub setup_once ($self, $add_global_event_processor, $get_current_hub) {
  ## no critic (Variables::RequireLocalizedPunctuationVars)
  $SIG{__DIE__} = sub {
    my $error = shift;
    
    # Don't interfere with exception objects  
    if (ref $error) {
      CORE::die $error;
    }
    
    # Capture the error in Sentry
    my $hub = $get_current_hub->();
    if ($hub) {
      $hub->capture_exception($error);
    }
    
    # Re-throw as Mojo::Exception for better stack traces
    Mojo::Exception->throw($error);
  };
}

1;
