#!/usr/bin/env perl

use strict;
use warnings;
use feature 'say';
use Time::HiRes qw(sleep time);

use lib 'lib';
use Sentry::SDK;

say "🔍 FOCUSED: Stack Collection Debug";
say "=" x 35;

# Initialize minimal profiling
Sentry::SDK->init({
    dsn => 'https://bc1b329862866abb9c8f70c5dac940aa@sentry.cgtmigration.com/9',
    traces_sample_rate => 1.0,
    profiles_sample_rate => 1.0,
    enable_profiling => 1,
    sampling_interval_us => 5000,
    debug => 0,  # Reduce noise
});

my $profiler = Sentry::SDK->get_profiler();

# Override _collect_stack_trace to show what's happening
{
    no strict 'refs';
    my $original_collect = \&Sentry::Profiling::StackSampler::_collect_stack_trace;
    
    *Sentry::Profiling::StackSampler::_collect_stack_trace = sub {
        my $self = shift;
        say "🔍 _collect_stack_trace called";
        
        my @frames = ();
        my $level = 1;
        my $max_depth = $self->max_stack_depth;
        
        say "   Stack trace analysis:";
        while (my @caller_info = caller($level)) {
            my ($package, $filename, $line, $subroutine) = @caller_info;
            
            say "     Level $level: $package :: $subroutine at $filename:$line";
            
            # Skip profiling internals
            if ($package =~ /^Sentry::Profiling/) {
                say "       -> SKIPPING (profiling internal)";
                $level++;
                next;
            }
            
            say "       -> KEEPING (application frame)";
            
            # Create frame object
            require Sentry::Profiling::Frame;
            my $frame = Sentry::Profiling::Frame->from_caller_info(
                $package, $filename, $line, $subroutine
            );
            
            push @frames, $frame->to_hash();
            
            $level++;
            last if $level > $max_depth;
        }
        
        say "   Collected " . scalar(@frames) . " application frames";
        return \@frames;
    };
}

# Override _sample_stack to show what happens
{
    no strict 'refs';
    my $original_sample = \&Sentry::Profiling::StackSampler::_sample_stack;
    
    *Sentry::Profiling::StackSampler::_sample_stack = sub {
        my $self = shift;
        say "🎯 _sample_stack called";
        
        my $profile = $self->_active_profile;
        if (!$profile) {
            say "   ❌ No active profile";
            return;
        }
        
        # Check for recursive sampling using the new flag approach
        if ($self->{_currently_sampling}) {
            say "   ❌ Blocked: recursive sampling detected";
            return;
        }
        
        # Set flag to prevent recursion
        local $self->{_currently_sampling} = 1;
        say "   ✅ Proceeding with sampling";
        
        eval {
            # Collect stack trace
            my $stack_frames = $self->_collect_stack_trace();
            
            if (@$stack_frames) {
                my $sample = {
                    timestamp => Time::HiRes::time(),
                    thread_id => "$$",
                    frames => $stack_frames,
                };
                
                $profile->add_sample($sample);
                my $new_count = $self->_sample_count + 1;
                $self->_sample_count($new_count);
                say "   ✅ Sample added! Count: $new_count";
            } else {
                say "   ❌ No frames to sample";
            }
        };
        
        if ($@) {
            say "   ❌ Error in sampling: $@";
        }
        
        # Schedule next sample if still active
        if ($self->_active_profile) {
            $self->_schedule_next_sample();
        }
    };
}

say "\n🎯 Starting profiler...";
my $profile = $profiler->start_profiler({ name => 'debug-test' });

if (!$profile) {
    die "Failed to start profiler";
}

say "✅ Profiler started\n";

# Test 1: Manual sampling from this context
say "📋 Test 1: Manual sample from main";
say "-" x 35;

my $sampler = $profiler->_sampler;
if ($sampler->can('sample_once')) {
    $sampler->sample_once();
} else {
    say "❌ No sample_once method";
}

# Test 2: Manual sampling from a function
say "\n📋 Test 2: Manual sample from function";
say "-" x 39;

sub test_function {
    say "Inside test_function, calling sample_once...";
    $sampler->sample_once();
}

test_function();

# Test 3: Manual sampling from nested functions
say "\n📋 Test 3: Manual sample from nested call";
say "-" x 41;

sub outer_function {
    inner_function();
}

sub inner_function {
    deep_function();
}

sub deep_function {
    say "Inside deep_function, calling sample_once...";
    $sampler->sample_once();
}

outer_function();

# Test 4: Wait for automatic sampling during work
say "\n📋 Test 4: Automatic sampling during work";
say "-" x 40;

say "Doing work for 1 second...";
my $work_start = time();

while (time() - $work_start < 1.0) {
    # Do CPU work
    my $result = fibonacci(15);
    sleep(0.01);
}

# Final results
say "\n🎯 Final Results";
say "-" x 17;

my $final_count = $sampler->get_sample_count;
say "Total samples collected: $final_count";

my $stopped = $profiler->stop_profiler();
if ($stopped) {
    my $stats = $stopped->get_stats();
    say "Profile stats:";
    say "  - Sample count: " . $stats->{sample_count};
    say "  - Unique frames: " . $stats->{unique_frames};
    say "  - Duration: " . sprintf("%.3fs", $stats->{duration} || 0);
} else {
    say "❌ Failed to stop profiler";
}

sub fibonacci {
    my ($n) = @_;
    return $n if $n <= 1;
    return fibonacci($n - 1) + fibonacci($n - 2);
}

__END__