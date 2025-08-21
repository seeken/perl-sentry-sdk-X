#!/usr/bin/env perl

=head1 NAME

real_world_profiling_example.pl - Practical Sentry profiling example

=head1 DESCRIPTION

This example demonstrates real-world usage of Sentry profiling in a typical
Perl application that processes data, makes HTTP requests, and performs
database operations. It shows how to configure profiling for different
environments and use cases.

=cut

use strict;
use warnings;
use feature 'say';
use JSON qw(encode_json decode_json);
use Time::HiRes qw(sleep time);

use lib '../lib';
use Sentry::SDK;

# Configuration for different environments
my %configs = (
    development => {
        dsn => $ENV{SENTRY_DSN} || 'https://test@sentry.io/1',
        traces_sample_rate => 1.0,        # Trace everything in dev
        profiles_sample_rate => 1.0,      # Profile everything in dev
        enable_profiling => 1,
        sampling_interval_us => 5000,     # 5ms - higher resolution
        adaptive_sampling => 0,           # Disable for consistent testing
        debug => 1,
    },
    
    staging => {
        dsn => $ENV{SENTRY_DSN} || 'https://test@sentry.io/1',
        traces_sample_rate => 0.5,        # 50% of requests
        profiles_sample_rate => 0.5,      # Profile 50% of traces
        enable_profiling => 1,
        sampling_interval_us => 10000,    # 10ms
        adaptive_sampling => 1,           # Handle variable load
        cpu_threshold_percent => 70,
        ignore_packages => ['Test::', 'DBI'],
    },
    
    production => {
        dsn => $ENV{SENTRY_DSN} || 'https://test@sentry.io/1',
        traces_sample_rate => 0.1,        # 10% of requests
        profiles_sample_rate => 0.2,      # Profile 20% of traces (2% overall)
        enable_profiling => 1,
        sampling_interval_us => 10000,    # 10ms
        adaptive_sampling => 1,           # Critical for production
        cpu_threshold_percent => 80,
        memory_threshold_mb => 500,
        max_stack_depth => 30,
        ignore_packages => ['Test::', 'DBI', 'LWP::', 'JSON::'],
    },
);

# Get environment from command line or ENV
my $env = $ARGV[0] || $ENV{APP_ENV} || 'development';
die "Unknown environment: $env" unless exists $configs{$env};

say "🚀 Starting Real-World Profiling Example";
say "Environment: $env";
say "=" x 50;

# Initialize Sentry with environment-specific config
Sentry::SDK->init($configs{$env});

say "✅ Sentry SDK initialized for $env environment";

# Simulate application startup
simulate_application_startup();

# Main application workflow
say "\n📊 Starting main application workflow...";

# Example 1: Web request processing
process_web_requests();

# Example 2: Background data processing
process_background_jobs();

# Example 3: Database operations
perform_database_operations();

# Example 4: API integrations
handle_external_apis();

say "\n✅ Application workflow complete!";
say "Check your Sentry project for profiling data.";

# Application simulation functions

sub simulate_application_startup {
    my $transaction = Sentry::SDK->start_transaction({
        name => 'app-startup',
        op => 'startup',
    });
    
    say "⚡ Application startup...";
    
    # Simulate loading configuration
    load_configuration();
    
    # Simulate database connection setup
    setup_database_connections();
    
    # Simulate cache warming
    warm_caches();
    
    $transaction->finish();
    say "   Startup complete";
}

sub process_web_requests {
    say "\n🌐 Processing web requests...";
    
    # Simulate multiple web requests
    for my $i (1..3) {
        my $transaction = Sentry::SDK->start_transaction({
            name => 'GET /api/users',
            op => 'http.server',
        });
        
        # Set transaction context
        Sentry::SDK->configure_scope(sub {
            my $scope = shift;
            $scope->set_tag('request_id', "req_$i");
            $scope->set_context('request', {
                method => 'GET',
                path => '/api/users',
                user_id => 1000 + $i,
            });
        });
        
        say "   Processing request $i...";
        
        # Simulate request processing
        authenticate_user();
        validate_permissions();
        fetch_user_data();
        format_response();
        
        $transaction->set_http_status(200);
        $transaction->finish();
    }
}

sub process_background_jobs {
    say "\n⚙️  Processing background jobs...";
    
    # Example of manual profiling for background work
    my $profile = Sentry::SDK->start_profiler({
        name => 'email-batch-processing'
    });
    
    # Simulate batch email processing
    for my $batch (1..3) {
        say "   Processing email batch $batch...";
        
        my $emails = fetch_pending_emails($batch);
        
        for my $email (@$emails) {
            process_email_template($email);
            send_email($email);
            update_email_status($email);
        }
    }
    
    my $completed_profile = Sentry::SDK->stop_profiler();
    
    if ($completed_profile) {
        my $stats = $completed_profile->get_stats();
        say "   📈 Profile stats: " . $stats->{sample_count} . " samples, " 
            . $stats->{unique_frames} . " unique frames";
    }
}

sub perform_database_operations {
    say "\n🗄️  Database operations...";
    
    # Profile database-intensive operations
    my $result = Sentry::SDK->profile(sub {
        
        # Simulate complex query
        complex_analytics_query();
        
        # Simulate data transformation
        transform_query_results();
        
        # Simulate bulk operations
        bulk_data_update();
        
        return "database_operations_complete";
    });
    
    say "   Database operations result: $result";
}

sub handle_external_apis {
    say "\n🔗 External API integrations...";
    
    my $transaction = Sentry::SDK->start_transaction({
        name => 'external-api-sync',
        op => 'external',
    });
    
    # Multiple API calls with different characteristics
    fetch_user_profiles_api();
    sync_inventory_data_api();
    update_payment_status_api();
    
    $transaction->finish();
}

# Helper functions that simulate real work

sub load_configuration {
    # Simulate config file parsing
    my $config = {
        database => { host => 'localhost', port => 5432 },
        cache => { ttl => 3600 },
        features => { new_ui => 1, profiling => 1 }
    };
    
    # Simulate JSON parsing overhead
    my $json = encode_json($config);
    my $parsed = decode_json($json);
    
    sleep(0.01);  # Simulate I/O
}

sub setup_database_connections {
    # Simulate database connection initialization
    for my $db (qw(primary replica analytics)) {
        sleep(0.005);  # Connection overhead
    }
}

sub warm_caches {
    # Simulate cache warming
    my @cache_keys = map { "cache_key_$_" } 1..20;
    
    for my $key (@cache_keys) {
        # Simulate cache computation
        my $value = complex_cache_computation($key);
    }
}

sub authenticate_user {
    # Simulate user authentication
    sleep(0.002);
    
    # Simulate token validation
    my $token = "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9";
    validate_jwt_token($token);
}

sub validate_permissions {
    # Simulate permission checking
    my @permissions = qw(read_users write_users admin);
    
    for my $perm (@permissions) {
        check_user_permission($perm);
    }
}

sub fetch_user_data {
    # Simulate database query
    my $query = "SELECT * FROM users WHERE active = 1 ORDER BY created_at DESC LIMIT 10";
    execute_database_query($query);
    
    # Simulate result processing
    for my $i (1..10) {
        format_user_record($i);
    }
}

sub format_response {
    # Simulate response formatting
    my $data = {
        users => [map { { id => $_, name => "User $_" } } 1..10],
        meta => { total => 10, page => 1 }
    };
    
    my $json = encode_json($data);
    return $json;
}

sub fetch_pending_emails {
    my $batch = shift;
    
    # Simulate fetching email batch
    sleep(0.01);
    
    return [map { 
        { 
            id => ($batch * 100) + $_, 
            to => "user$_\@example.com",
            subject => "Weekly Newsletter #$_",
            template => 'newsletter'
        } 
    } 1..50];
}

sub process_email_template {
    my $email = shift;
    
    # Simulate template processing
    my $template = load_email_template($email->{template});
    my $content = render_template($template, $email);
    
    $email->{content} = $content;
}

sub send_email {
    my $email = shift;
    
    # Simulate SMTP sending
    sleep(0.001);
    
    $email->{sent_at} = time();
}

sub update_email_status {
    my $email = shift;
    
    # Simulate database update
    my $query = "UPDATE emails SET status = 'sent', sent_at = ? WHERE id = ?";
    execute_database_query($query, $email->{sent_at}, $email->{id});
}

sub complex_analytics_query {
    # Simulate complex analytics query
    sleep(0.05);
    
    # Simulate CPU-intensive aggregation
    my $result = 0;
    for my $i (1..1000) {
        $result += $i * $i;
    }
    
    return $result;
}

sub transform_query_results {
    # Simulate data transformation
    my @data = map { 
        { 
            id => $_, 
            computed_field => $_ * 2.5,
            category => $_ % 5 ? 'A' : 'B' 
        } 
    } 1..500;
    
    # Simulate sorting
    @data = sort { $a->{computed_field} <=> $b->{computed_field} } @data;
    
    return \@data;
}

sub bulk_data_update {
    # Simulate bulk database operations
    for my $i (1..100) {
        execute_database_query(
            "UPDATE analytics SET processed = 1 WHERE id = ?", 
            $i
        );
    }
}

sub fetch_user_profiles_api {
    say "   Fetching user profiles from external API...";
    
    # Simulate HTTP request latency
    sleep(0.1);
    
    # Simulate JSON parsing
    my $response = {
        users => [map { { id => $_, name => "External User $_" } } 1..20]
    };
    
    my $json = encode_json($response);
    my $parsed = decode_json($json);
    
    return $parsed;
}

sub sync_inventory_data_api {
    say "   Syncing inventory data...";
    
    # Simulate slower API
    sleep(0.2);
    
    # Simulate data processing
    for my $item (1..100) {
        process_inventory_item($item);
    }
}

sub update_payment_status_api {
    say "   Updating payment statuses...";
    
    # Simulate payment processor API
    sleep(0.05);
    
    my @payments = 1..50;
    for my $payment (@payments) {
        validate_payment_status($payment);
    }
}

# Low-level helper functions

sub complex_cache_computation {
    my $key = shift;
    
    # Simulate expensive cache computation
    my $result = 0;
    for my $i (1..100) {
        $result += length($key) * $i;
    }
    
    return $result;
}

sub validate_jwt_token {
    my $token = shift;
    
    # Simulate JWT validation overhead
    for my $i (1..10) {
        my $hash = unpack('H*', $token);
    }
}

sub check_user_permission {
    my $permission = shift;
    
    # Simulate permission lookup
    sleep(0.001);
    
    return length($permission) > 4;
}

sub execute_database_query {
    my ($query, @params) = @_;
    
    # Simulate database query execution time
    my $complexity = length($query) + scalar(@params);
    sleep($complexity / 100000);  # Scale with query complexity
    
    return "query_result";
}

sub format_user_record {
    my $user_id = shift;
    
    # Simulate record formatting
    my $record = {
        id => $user_id,
        name => "User $user_id",
        email => "user$user_id\@example.com",
        created_at => time() - (86400 * $user_id),
    };
    
    return $record;
}

sub load_email_template {
    my $template_name = shift;
    
    # Simulate template loading
    sleep(0.002);
    
    return "Hello {{name}}, this is template $template_name";
}

sub render_template {
    my ($template, $data) = @_;
    
    # Simulate template rendering
    my $content = $template;
    $content =~ s/\{\{(\w+)\}\}/$data->{$1} || ''/ge;
    
    return $content;
}

sub process_inventory_item {
    my $item_id = shift;
    
    # Simulate item processing
    my $processing_time = ($item_id % 10) / 10000;  # Variable processing time
    sleep($processing_time);
}

sub validate_payment_status {
    my $payment_id = shift;
    
    # Simulate payment validation
    sleep(0.001);
    
    return $payment_id % 10 != 0;  # 90% success rate
}

__END__

=head1 USAGE

Run this example with different environment configurations:

    # Development environment (verbose profiling)
    perl real_world_profiling_example.pl development
    
    # Staging environment (balanced profiling)
    perl real_world_profiling_example.pl staging
    
    # Production environment (minimal overhead)
    perl real_world_profiling_example.pl production

Set your Sentry DSN:

    export SENTRY_DSN="https://your-dsn@sentry.io/project-id"
    perl real_world_profiling_example.pl production

=head1 WHAT TO EXPECT

This example will generate several types of profiling data:

1. **Application Startup**: Profile initialization overhead
2. **Web Requests**: Multiple HTTP request handling profiles  
3. **Background Jobs**: Batch processing with manual profiling
4. **Database Operations**: Query-heavy workload profiling
5. **API Integrations**: External service call profiling

In Sentry, you'll see:
- Flame graphs showing call hierarchies
- Hot spots in email processing and database operations
- Performance differences between API calls
- Memory allocation patterns

=head1 LEARNING POINTS

- Different profiling configurations for different environments
- Manual vs automatic profiling strategies
- Transaction context and metadata correlation
- Performance overhead measurement
- Real-world profiling use cases

=cut