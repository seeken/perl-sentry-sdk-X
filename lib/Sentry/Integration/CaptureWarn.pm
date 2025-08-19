package Sentry::Integration::CaptureWarn;
use Mojo::Base 'Sentry::Integration::Base', -signatures;

# https://github.com/getsentry/sentry-javascript/blob/master/packages/integrations/src/captureconsole.ts

sub setup_once ($self, $add_global_event_processor, $get_current_hub) {
  # Warning capture integration - captures Perl warnings as Sentry events
  $SIG{__WARN__} = sub {
    my $warning = shift;
    chomp $warning;
    
    my $hub = $get_current_hub->();
    return unless $hub;
    
    $hub->capture_message($warning, 'warning', {
      contexts => {
        warning => {
          message => $warning,
          source => 'perl_warn',
        }
      }
    });
    
    # Still output the warning normally
    warn $warning . "\n";
  };
}

1;