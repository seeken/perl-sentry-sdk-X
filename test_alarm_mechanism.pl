#!/usr/bin/env perl

use strict;
use warnings;
use feature 'say';
use Time::HiRes qw(time alarm sleep);

say "🔍 Testing SIGALRM mechanism";
say "=" x 30;

my $alarm_count = 0;
my $start_time = time();

# Set up alarm handler
$SIG{ALRM} = sub {
    $alarm_count++;
    my $elapsed = time() - $start_time;
    say "Alarm $alarm_count at ${elapsed}s";
    
    # Schedule next alarm if we haven't had 5 yet
    if ($alarm_count < 5) {
        alarm(0.001);  # 1ms
    }
};

say "Starting alarm test with 1ms intervals...";
alarm(0.001);  # Start with 1ms

# Do some work while alarms fire
my $work_result = 0;
for my $i (1..10000) {
    $work_result += $i * $i;
    if ($i % 1000 == 0) {
        sleep(0.002);  # 2ms - should trigger multiple alarms
    }
}

# Wait a bit more
sleep(0.1);

# Cancel any remaining alarms
alarm(0);

say "Work result: $work_result";
say "Total alarms received: $alarm_count";
say "Expected: 5 alarms";

if ($alarm_count == 0) {
    say "❌ No alarms received - signal mechanism not working";
} elsif ($alarm_count < 5) {
    say "⚠️  Only $alarm_count/5 alarms received - partial success";
} else {
    say "✅ All alarms received - signal mechanism working";
}

# Test 2: Test stack trace collection during alarm
say "\n🔍 Testing stack trace in alarm handler";
say "-" x 40;

my @collected_stacks = ();

$SIG{ALRM} = sub {
    my @stack = ();
    my $level = 1;
    
    while (my @caller_info = caller($level)) {
        my ($package, $filename, $line, $subroutine) = @caller_info;
        push @stack, {
            package => $package,
            file => $filename,
            line => $line,
            sub => $subroutine,
        };
        $level++;
        last if $level > 10;  # Limit depth
    }
    
    push @collected_stacks, \@stack;
    say "  Collected stack with " . scalar(@stack) . " frames";
};

say "Testing stack collection during work...";
alarm(0.005);  # 5ms

# Do nested work to create a stack
sub level1 { level2(); }
sub level2 { level3(); }
sub level3 {
    for my $i (1..1000) {
        my $result = $i * $i;
        if ($i % 100 == 0) {
            sleep(0.001);  # Allow alarm to fire
        }
    }
}

level1();

alarm(0);  # Cancel
sleep(0.01);  # Let any pending alarms complete

say "Stacks collected: " . scalar(@collected_stacks);
if (@collected_stacks) {
    say "✅ Stack collection during alarms working";
    say "Sample stack (first):";
    my $first_stack = $collected_stacks[0];
    for my $i (0..2) {  # Show first 3 frames
        last unless $first_stack->[$i];
        my $frame = $first_stack->[$i];
        say "    $i: $frame->{package}::$frame->{sub} at $frame->{file}:$frame->{line}";
    }
} else {
    say "❌ No stack traces collected during alarms";
}

say "\n🎯 Summary";
say "=" x 15;
say "Alarm mechanism: " . ($alarm_count > 0 ? "WORKING ✅" : "BROKEN ❌");
say "Stack collection: " . (@collected_stacks > 0 ? "WORKING ✅" : "BROKEN ❌");

__END__