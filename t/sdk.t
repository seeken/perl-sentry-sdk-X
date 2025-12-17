use Mojo::Base -strict, -signatures;

use Mojo::File;
# curfile missing in Mojolicious@^8. The dependency shall not be updated for
# the time being. For this reason `curfile` is duplicated for now.
# use lib curfile->sibling('lib')->to_string;
# See https://github.com/mojolicious/mojo/blob/4093223cae00eb516e38f2226749d2963597cca3/lib/Mojo/File.pm#L36
use lib Mojo::File->new(Cwd::realpath((caller)[1]))->sibling('lib')->to_string;

use Mock::Sentry::Client;
use Mojo::Exception;
use Mojo::Util 'dumper';
use Sentry::Hub;
use Sentry::Logger;
use Sentry::SDK;
use Sentry::Severity;
use Test::Exception;
use Test::Snapshot;
use Test::Spec;
use UUID::Tiny 'is_UUID_string';
use version;

describe 'Sentry::SDK' => sub {
  my $hub;

  before each => sub {
    $hub = Sentry::Hub->get_current_hub();
    $hub->reset();
  };

  it 'has a $VERSION' => sub {
    isa_ok $Sentry::SDK::VERSION => 'version';
  };

  describe 'init()' => sub {
    before each => sub {
      $Sentry::SDK::VERSION = version->declare('v1.1.1');

      Sentry::SDK->init({
        release            => 'my release',
        dsn                => 'abc',
        traces_sample_rate => 0.5,
        environment        => 'my env',
        debug              => 1,
      });
    };

    it 'creates a client' => sub {
      isa_ok $hub->client, 'Sentry::Client';
    };

    it 'passes options to the client' => sub {
      my $options = $hub->client->get_options;
      # Check key options are passed through correctly
      is($options->{dsn}, 'abc', 'dsn passed');
      is($options->{environment}, 'my env', 'environment passed');
      is($options->{release}, 'my release', 'release passed');
      is($options->{traces_sample_rate}, '0.5', 'traces_sample_rate passed');
      is($options->{debug}, 1, 'debug passed');
      ok(exists $options->{integrations}, 'integrations exist');
    };

    # TODO: Implement logger active_contexts if needed
    # it 'sets the logger context' => sub {
    #   is_deeply(Sentry::Logger->logger->active_contexts, ['.*']);
    # };

    it 'reads options from ENV' => sub {
      local $ENV{SENTRY_DSN}                = 'DSN from env';
      local $ENV{SENTRY_RELEASE}            = 'release from env';
      local $ENV{SENTRY_TRACES_SAMPLE_RATE} = '0.123';
      local $ENV{SENTRY_ENVIRONMENT}        = 'environment from env';

      Sentry::SDK->init();

      my $options = $hub->client->get_options;
      # Check key options are read from ENV correctly
      is($options->{dsn}, 'DSN from env', 'dsn from env');
      is($options->{environment}, 'environment from env', 'environment from env');
      is($options->{release}, 'release from env', 'release from env');
      is($options->{traces_sample_rate}, '0.123', 'traces_sample_rate from env');
    };

    it 'passes in_app_include and in_app_exclude to client' => sub {
      Sentry::SDK->init({
        dsn => 'test-dsn',
        in_app_include => ['MyApp::', 'MyCompany::'],
        in_app_exclude => ['ThirdParty::', 'Legacy::'],
      });

      my $options = $hub->client->get_options;
      is_deeply($options->{in_app_include}, ['MyApp::', 'MyCompany::'],
        'in_app_include passed to client');
      is_deeply($options->{in_app_exclude}, ['ThirdParty::', 'Legacy::'],
        'in_app_exclude passed to client');
    };

    it 'disables SDK if DSN is empty' => sub {
      Sentry::SDK->init({ dsn => '' });

      is($hub->client, undef, 'client is undefined');

      lives_ok { Sentry::SDK->capture_message('foo') };
    };
  };

  describe 'message sending' => sub {
    my $client;

    before each => sub {
      $client = Mock::Sentry::Client->new;
      $hub->client($client);
    };

    it 'capture_message()' => sub {
      Sentry::SDK->capture_message('foo', Sentry::Severity->Warning);

      my $captured = $client->_captured_message;
      is $captured->{level}   => 'warning';
      is $captured->{message} => 'foo';
      isa_ok $captured->{scope}, 'Sentry::Hub::Scope';
      is_UUID_string $captured->{hint}{event_id};
    };

    it 'capture_event()' => sub {
      my $event   = { foo   => 'bar' };
      my $context = { level => Sentry::Severity->Error };
      Sentry::SDK->capture_event($event, $context);

      my $captured = $client->_captured_message;
      isa_ok $captured->{scope}, 'Sentry::Hub::Scope';
      is_deeply $captured->{event},                 $event;
      is_deeply $captured->{hint}{capture_context}, $context;
      is_UUID_string $captured->{hint}{event_id};
    };

    it 'capture_exception()' => sub {
      my $exception = Mojo::Exception->new('ohoh');
      my $context   = { level => Sentry::Severity->Warning };
      Sentry::SDK->capture_exception($exception, $context);

      my $captured = $client->_captured_message;
      isa_ok $captured->{scope}, 'Sentry::Hub::Scope';
      is_deeply $captured->{exception}, $exception;
      is_deeply $captured->{hint}{original_exception} => $exception;
      is_deeply $captured->{hint}{capture_context}, $context;
      is_UUID_string $captured->{hint}{event_id};
    };
  };

  it 'configure_scope()' => sub {
    my %user = (id => 1, email => 'john.doe@example.com');

    Sentry::SDK->configure_scope(sub ($scope) {
      $scope->set_tag(foo => 'bar');
      $scope->set_user({%user});
    });

    my $scope = $hub->get_current_scope();
    is_deeply $scope->tags => { foo => 'bar' };
    is_deeply $scope->user => \%user;
  };

  it 'add_breadcrumb()' => sub {
    my %breadcrumb = (
      type      => 'query',
      category  => 'mycat',
      data      => { my => 'data' },
      timestamp => time,
    );

    Sentry::SDK->add_breadcrumb({%breadcrumb});

    is_deeply $hub->get_current_scope()->breadcrumbs, [{%breadcrumb}];
  };

  it 'start_transaction()' => sub {
    Sentry::SDK->init({ dsn => 'abc', traces_sample_rate => 1, });

    my $tx
      = Sentry::SDK->start_transaction(
        { name     => 'my transaction name', op => 'my.op', },
        { 'mydata' => { foo => 'bar' } });

    isa_ok $tx, 'Sentry::Tracing::Transaction';
    is $tx->name => 'my transaction name';
    is $tx->op   => 'my.op';
    ok defined $tx->start_timestamp;
    is_deeply $tx->tags => {
      "__sentry_sampleRate"     => 1,
      "__sentry_samplingMethod" => "client_rate"
    };
    ok $tx->sampled;
  };

  describe 'traces_sampler' => sub {
    it 'uses traces_sampler callback when provided' => sub {
      my @sampler_calls;

      Sentry::SDK->init({
        dsn => 'abc',
        traces_sample_rate => 0,  # Would normally not sample
        traces_sampler => sub {
          my ($ctx) = @_;
          push @sampler_calls, $ctx;
          return 1;  # Force sample
        },
      });

      my $tx = Sentry::SDK->start_transaction({
        name => 'test-transaction',
        op   => 'test.op',
      });

      ok $tx->sampled, 'Transaction sampled via traces_sampler';
      is scalar(@sampler_calls), 1, 'Sampler called once';
      is $sampler_calls[0]->{transaction_context}{name}, 'test-transaction',
        'Sampler receives transaction name';
      is $sampler_calls[0]->{transaction_context}{op}, 'test.op',
        'Sampler receives transaction op';
      is $tx->tags->{__sentry_samplingMethod}, 'traces_sampler',
        'Sampling method is traces_sampler';
    };

    it 'traces_sampler can return 0 to never sample' => sub {
      Sentry::SDK->init({
        dsn => 'abc',
        traces_sample_rate => 1,  # Would normally always sample
        traces_sampler => sub { return 0 },  # Never sample
      });

      my $tx = Sentry::SDK->start_transaction({
        name => 'never-sample',
        op   => 'test',
      });

      ok !$tx->sampled, 'Transaction not sampled when sampler returns 0';
    };

    it 'traces_sampler returning undef falls back to traces_sample_rate' => sub {
      Sentry::SDK->init({
        dsn => 'abc',
        traces_sample_rate => 1,
        traces_sampler => sub { return undef },  # Fall back
      });

      my $tx = Sentry::SDK->start_transaction({
        name => 'fallback-test',
        op   => 'test',
      });

      ok $tx->sampled, 'Transaction sampled via fallback to traces_sample_rate';
      is $tx->tags->{__sentry_samplingMethod}, 'client_rate',
        'Sampling method is client_rate (fallback)';
    };

    it 'traces_sampler receives custom sampling context' => sub {
      my $received_ctx;

      Sentry::SDK->init({
        dsn => 'abc',
        traces_sampler => sub {
          my ($ctx) = @_;
          $received_ctx = $ctx;
          return 1;
        },
      });

      my $tx = Sentry::SDK->start_transaction(
        { name => 'ctx-test', op => 'test' },
        { request_path => '/api/slow', user_id => 123 }
      );

      is $received_ctx->{request_path}, '/api/slow',
        'Custom context passed to sampler';
      is $received_ctx->{user_id}, 123,
        'Custom context values accessible';
    };

    it 'traces_sampler can conditionally sample based on context' => sub {
      Sentry::SDK->init({
        dsn => 'abc',
        traces_sample_rate => 0.1,
        traces_sampler => sub {
          my ($ctx) = @_;
          # Always sample /api/critical paths
          if ($ctx->{request_path} && $ctx->{request_path} =~ m{^/api/critical}) {
            return 1;
          }
          # Never sample health checks
          if ($ctx->{transaction_context}{name} =~ /health/) {
            return 0;
          }
          # Fall back to default rate for everything else
          return undef;
        },
      });

      # Critical path - always sampled
      my $critical_tx = Sentry::SDK->start_transaction(
        { name => '/api/critical/endpoint', op => 'http' },
        { request_path => '/api/critical/endpoint' }
      );
      ok $critical_tx->sampled, 'Critical path always sampled';

      # Health check - never sampled
      my $health_tx = Sentry::SDK->start_transaction(
        { name => '/health', op => 'http' },
        {}
      );
      ok !$health_tx->sampled, 'Health check never sampled';
    };

    it 'explicit sampled=1 overrides traces_sampler' => sub {
      Sentry::SDK->init({
        dsn => 'abc',
        traces_sampler => sub { return 0 },  # Would not sample
      });

      my $tx = Sentry::SDK->start_transaction({
        name    => 'explicit-sample',
        op      => 'test',
        sampled => 1,  # Force sample
      });

      ok $tx->sampled, 'Explicit sampled=1 overrides sampler';
      is $tx->tags->{__sentry_samplingMethod}, 'explicitly_set',
        'Sampling method is explicitly_set';
    };
  };
};

runtests;
