package Sentry::Integration;
use Mojo::Base -base, -signatures;

use Sentry::Hub;
use Sentry::Hub::Scope;

# Remove global integrations - these should be managed through client options
sub setup ($package, $integrations = []) {
  foreach my $integration (grep { !$_->initialized } @$integrations) {
    $integration->setup_once(
      Sentry::Hub::Scope->can('add_global_event_processor'),
      Sentry::Hub->can('get_current_hub')
    );
    $integration->initialized(1);
  }
}

1;
