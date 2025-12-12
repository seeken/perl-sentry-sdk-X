use Mojo::Base -strict, -signatures;

use Mojo::File;
# curfile missing in Mojolicious@^8. The dependency shall not be updated for
# the time being. For this reason `curfile` is duplicated for now.
# use lib curfile->sibling('lib')->to_string;
# See https://github.com/mojolicious/mojo/blob/4093223cae00eb516e38f2226749d2963597cca3/lib/Mojo/File.pm#L36
use lib Mojo::File->new(Cwd::realpath((caller)[1]))->sibling('lib')->to_string;

use Config qw(%Config);
use Mock::Sentry::SourceFileRegistry;
use Mojo::Exception;
use Mojo::Home;
use Mojo::JSON qw(decode_json encode_json);
use Sentry::Stacktrace::Frame;
use Test::Exception;
use Test::Spec;

describe 'Sentry::Stacktrace::Frame' => sub {
  my $home;
  my $frame;
  my $frame_json;

  before each => sub {
    $home  = Mojo::Home->new->detect;
    $frame = Sentry::Stacktrace::Frame->new(
      _source_file_registry => Mock::Sentry::SourceFileRegistry->new,
      module                => 'My::Module',
      filename              => $home->child('My', 'Module.pm')->to_string,
      line                  => 1,
      subroutine            => 'my_method',
    );
    $frame_json = decode_json encode_json $frame;
  };

  describe 'External frames' => sub {
    it 'absolute external path' => sub {
      ok $frame_json->{in_app};

      $frame->filename('/external/External/Module.pm');
      $frame_json = decode_json encode_json $frame;
      ok !$frame_json->{in_app};
    };

    it 'CPAN modules' => sub {
      ok $frame_json->{in_app};

      $frame->filename(
        $home->child($Config{siteprefix}, 'Module.pm')->to_string);

      $frame_json = decode_json encode_json $frame;
      ok !$frame_json->{in_app};
    };
  };

  it 'correctly identifies local frames as in-app' => sub {
    $frame->filename('lib/My/Module.pm');
    $frame_json = decode_json encode_json $frame;
    ok $frame_json->{in_app};
  };

  describe 'in_app_include and in_app_exclude options' => sub {
    it 'in_app_include marks matching modules as in-app' => sub {
      # External module that would normally be NOT in-app
      $frame->filename('/external/External/Module.pm');
      $frame->module('External::Module');
      $frame_json = decode_json encode_json $frame;
      ok !$frame_json->{in_app}, 'External module is not in-app by default';

      # Add include pattern for External::
      $frame->in_app_include(['External::']);
      $frame_json = decode_json encode_json $frame;
      ok $frame_json->{in_app}, 'Module matches in_app_include, now in-app';
    };

    it 'in_app_exclude marks matching modules as NOT in-app' => sub {
      # Local module that would normally be in-app
      $frame->filename('lib/My/Module.pm');
      $frame->module('My::Module');
      $frame->in_app_include([]);  # Reset include
      $frame_json = decode_json encode_json $frame;
      ok $frame_json->{in_app}, 'Local module is in-app by default';

      # Add exclude pattern for My::
      $frame->in_app_exclude(['My::']);
      $frame_json = decode_json encode_json $frame;
      ok !$frame_json->{in_app}, 'Module matches in_app_exclude, now NOT in-app';
    };

    it 'in_app_include takes precedence over in_app_exclude' => sub {
      $frame->filename('lib/My/Module.pm');
      $frame->module('My::Module');
      # Both match - include should win
      $frame->in_app_include(['My::']);
      $frame->in_app_exclude(['My::']);
      $frame_json = decode_json encode_json $frame;
      ok $frame_json->{in_app}, 'in_app_include takes precedence over in_app_exclude';
    };

    it 'handles multiple prefixes' => sub {
      $frame->filename('/external/Vendor/Package.pm');
      $frame->module('Vendor::Package');
      $frame->in_app_include(['App::', 'MyCompany::', 'Vendor::']);
      $frame->in_app_exclude([]);
      $frame_json = decode_json encode_json $frame;
      ok $frame_json->{in_app}, 'Third include prefix matches';

      $frame->in_app_include([]);
      $frame->in_app_exclude(['External::', 'ThirdParty::', 'Vendor::']);
      $frame_json = decode_json encode_json $frame;
      ok !$frame_json->{in_app}, 'Third exclude prefix matches';
    };

    it 'handles undef module gracefully' => sub {
      $frame->module(undef);
      $frame->in_app_include(['SomeModule::']);
      $frame->in_app_exclude(['OtherModule::']);
      lives_ok { $frame_json = decode_json encode_json $frame }
        'No crash with undef module';
    };

    it 'handles empty prefix strings' => sub {
      $frame->filename('lib/My/Module.pm');
      $frame->module('My::Module');
      $frame->in_app_include(['', 'My::']);  # Empty prefix ignored
      $frame->in_app_exclude([]);
      $frame_json = decode_json encode_json $frame;
      ok $frame_json->{in_app}, 'Empty prefix in include is ignored';
    };
  };

  it 'has file context' => sub {
    is $frame_json->{pre_context},  'pre context';
    is $frame_json->{context_line}, 'context line';
    is $frame_json->{post_context}, 'post context';
  };

  it 'has relative filename' => sub {
    is $frame_json->{file_name}, 'My/Module.pm';
  };
};

runtests;

