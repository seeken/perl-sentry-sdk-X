#!/usr/bin/env perl

use strict;
use warnings;
use feature 'say';
use Time::HiRes qw(time sleep);

use lib 'lib';
use Sentry::Profiling::StackSampler;
use Sentry::Profiling::Profile;

say "🔍 Debugging StackSampler with verbose logging";
say "=" x 50;

# Create profile and sampler
my $profile = Sentry::Profiling::Profile->new(name => 'debug-test');
my $sampler = Sentry::Profiling::StackSampler->new(
    max_stack_depth => 20
);

say "Created profile and sampler";

# Add debugging to see what's happening
my $sample_attempts = 0;
my $sample_successes = 0;

# Override the _sample_stack method to add debugging
{
    no strict 'refs';
    my $original_sample = \&Sentry::Profiling::StackSampler::_sample_stack;
    
    *Sentry::Profiling::StackSampler::_sample_stack = sub {
        my $self = shift;
        $sample_attempts++;
        say "  📊 Sample attempt #$sample_attempts";
        
        # Call original method
        my $result = $original_sample->($self, @_);
        
        # Check if sample was added
        my $stats = $self->_active_profile->get_stats() if $self->_active_profile;
        if ($stats && $stats->{sample_count} > $sample_successes) {
            $sample_successes = $stats->{sample_count};
            say "    ✅ Sample #$sample_successes added successfully";
        } else {
            say "    ❌ Sample was not added";
        }
        
        return $result;
    };
}

# Override _collect_stack_trace to add debugging
{
    no strict 'refs';
    my $original_collect = \&Sentry::Profiling::StackSampler::_collect_stack_trace;
    
    *Sentry::Profiling::StackSampler::_collect_stack_trace = sub {
        my $self = shift;
        say "    🔍 Collecting stack trace...";
        
        my $frames = $original_collect->($self, @_);
        say "    📚 Collected " . scalar(@$frames) . " frames";
        
        if (@$frames) {
            say "    📋 First few frames:";
            for my $i (0..2) {
                last unless $frames->[$i];
                my $frame = $frames->[$i];
                say "      $i: " . ($frame->{function} || 'unknown') . 
                    " at " . ($frame->{filename} || 'unknown') . 
                    ":" . ($frame->{lineno} || 'unknown');
            }
        }
        
        return $frames;
    };
}

say "\nStarting sampling with 5ms intervals...";
$sampler->start($profile, 5000);  # 5ms

say "Sampler started, doing work...";

# Generate work with nested calls
sub work_level1 {
    work_level2();
}

sub work_level2 {
    work_level3();
}

sub work_level3 {
    for my $i (1..2000) {
        my $result = fibonacci($i % 15);
        if ($i % 200 == 0) {
            sleep(0.01);  # 10ms - should allow multiple samples
        }
    }
}

# Do the work
work_level1();

say "\nWork complete, waiting a bit more...";
sleep(0.1);

say "\nStopping sampler...";
$sampler->stop();

# Get final stats
my $final_stats = $profile->get_stats();
say "\n📊 Final Results:";
say "-" x 20;
say "Sample attempts: $sample_attempts";
say "Sample successes: $sample_successes";
say "Profile sample count: " . $final_stats->{sample_count};
say "Profile unique frames: " . $final_stats->{unique_frames};
say "Profile duration: " . sprintf("%.3fs", $final_stats->{duration} || 0);

if ($final_stats->{sample_count} > 0) {
    say "✅ Sampling worked!";
    
    # Try creating envelope
    my $envelope = $profile->to_envelope_item();
    if ($envelope) {
        say "✅ Envelope creation successful";
        say "   Type: " . $envelope->{type};
        say "   Has data: " . (defined $envelope->{data} ? "YES" : "NO");
    } else {
        say "❌ Envelope creation failed";
    }
} else {
    say "❌ No samples collected";
    
    # Let's try manual sampling
    say "\n🔧 Trying manual sample...";
    $sampler->sample_once() if $sampler->can('sample_once');
    
    my $manual_stats = $profile->get_stats();
    say "After manual sample: " . $manual_stats->{sample_count} . " samples";
}

sub fibonacci {
    my ($n) = @_;
    return $n if $n <= 1;
    return fibonacci($n - 1) + fibonacci($n - 2);
}

__END__