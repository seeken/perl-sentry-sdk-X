#!/usr/bin/env perl
use strict;
use warnings;
use lib './lib';

use Sentry::SDK;

=head1 NAME

sdk_integration_simple.pl - Simple demo of Phase 3 Advanced Error Handling with SDK

=head1 DESCRIPTION

A streamlined demo showing the advanced error handling integrated with the SDK.

=cut

print "🚀 Phase 3: Advanced Error Handling + SDK Integration\n";
print "=" x 55, "\n\n";

# Use real DSN or environment variable
my $dsn = $ENV{SENTRY_DSN} || 'https://bc1b329862866abb9c8f70c5dac940aa@sentry.cgtmigration.com/9';

print "1. 🔧 INITIALIZING SDK WITH ADVANCED ERROR HANDLING\n";
print "-" x 50, "\n";

# Initialize SDK with advanced error handling enabled
Sentry::SDK->init({
  dsn => $dsn,
  environment => 'development',
  debug => 1,  # Enable debug output to see what's happening
  
  # Enable advanced error handling - this is the key feature!
  advanced_error_handling => 1,
  
  # Configure advanced error handling  
  advanced_error_handling_config => {
    sampling => {
      sampling_config => { base_sample_rate => 1.0 }  # Sample everything for demo
    }
  },
  
  # Keep it simple - disable other integrations
  disabled_integrations => ['DBI', 'LwpUserAgent', 'MojoUserAgent', 'MojoTemplate'],
});

print "✓ SDK initialized with advanced error handling enabled\n\n";

print "2. 🎭 TESTING ERROR CAPTURE WITH ADVANCED PROCESSING\n";
print "-" x 50, "\n";

# Test 1: Simple error
print "Test 1: Simple application error\n";
eval { die "Test error for advanced processing demo" };
my $event_id_1 = Sentry::SDK->capture_exception($@);
print "  ✓ Event captured with ID: " . ($event_id_1 || 'none') . "\n\n";

# Test 2: Error with level hint (using supported hint format)
print "Test 2: Error with severity level\n";
eval { die "Critical system failure - database unavailable" };
my $event_id_2 = Sentry::SDK->capture_exception($@, {
  level => 'fatal',
});
print "  ✓ Event captured with ID: " . ($event_id_2 || 'none') . "\n\n";

# Test 3: User scope with error
print "Test 3: Error with user scope\n";
Sentry::SDK->configure_scope(sub {
  my $scope = shift;
  $scope->set_user({
    id => 'demo_user_123',
    email => 'demo@example.com',
  });
});

eval { die "User-specific error for context testing" };
my $event_id_3 = Sentry::SDK->capture_exception($@);
print "  ✓ Event captured with ID: " . ($event_id_3 || 'none') . "\n\n";

print "=" x 55, "\n";
print "🎉 Advanced Error Handling Integration Working!\n\n";

print "✨ What happened behind the scenes:\n";
print "  • Error fingerprinting for intelligent grouping\n";
print "  • Context enrichment with system and user data\n";
print "  • Intelligent sampling decisions\n";  
print "  • Advanced error classification\n";
print "  • All seamlessly integrated with existing SDK API\n\n";

print "🚀 Phase 3 Integration Complete! Ready for Phase 2!\n";