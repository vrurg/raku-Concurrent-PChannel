use v6.c;
use Test::Async;
use Concurrent::PChannel;

BEGIN $*SCHEDULER = ThreadPoolScheduler.new: :max_threads($*KERNEL.cpu-cores * 10);

plan 8; #, :test-jobs($*KERNEL.cpu-cores * 8);

sub test-robust($message, :$count, :$prios, :$senders, :$receivers, :$with-close = True) {
    subtest $message, -> \suite {
#        note "============================ ", suite.message;
        my $expected = $senders * $count;
        my $report-progress = ? %*ENV<ROBUST_REPORT_PROGRESS>;
        my $on-terminal = $*OUT.t;
        plan 5;
        diag "Using $senders senders, $receivers receivers on $count item over $prios priorities"
            if $on-terminal || $report-progress;

        my $pchannel = Concurrent::PChannel.new: :priorities($prios);
        my $pc-ready = Promise.new;
        my $pc-read = Promise.new;
        my $channel = Channel.new;
        my $ch-ready = Promise.new;

        my $pc-read-total = 0;
        my $ch-read-total = 0;

        my atomicint $pc-read-count = 0;
        my atomicint $ch-read-count = 0;
        my atomicint $ch-write-count = 0;
        my @pc-readers;
        my @ch-readers;
        for ^$receivers -> $rn {
            @pc-readers.push: start {
                CATCH {
                    default {
                        note "==ON RECEIVE!=== ", $_, "\n", .backtrace.Str;
                        exit 1;
                    }
                }
                await $pc-ready;
                my $st = now;
                my $v;
                loop {
                    $v = $pchannel.receive;
                    last unless $v ~~ Int;
                    ++⚛$pc-read-count;
                }
                $v.so if $v ~~ Failure && $v.exception ~~ X::PChannel::OpOnClosed;
                my $et = now;
#                note "--- [{$*THREAD.id}] PC Reader $rn Done, elems: ", $pchannel.elems;
                cas $pc-read-total, { $_ + $et - $st };
            };
            @ch-readers.push: start {
                await $ch-ready;
                my $st = now;
                my $v;
                loop {
                    $v = try $channel.receive;
                    last unless $v ~~ Int;
                    ++⚛$ch-read-count;
                }
                my $et = now;
                cas $ch-read-total, { $_ + $et - $st };
            };
        }

        my @pc-writers;
        my @ch-writers;
        my $pc-write-total = 0;
        my $ch-write-total = 0;
        my atomicint $pc-write-count = 0;
        for ^$senders -> $sender {
            @pc-writers.push: start {
                CATCH {
                    default {
                        note "==ON SEND!=== ", $_;
                        exit 1;
                    }
                }
#                note "PC SEND? ", $pc-ready.WHICH;
                await $pc-ready;
#                note "PC SENDING";
                my $st = now;
                for ^$count {
                    $pchannel.send: ($sender * $count + $_), $prios.rand.Int;
                    # $pchannel.send: ($sender * $count + $_), (($sender * $count + $_) mod $prios);
                    ++⚛$pc-write-count;
                }
                my $et = now;
                cas $pc-write-total, { $_ + $et - $st }
            }
            @ch-writers.push: start {
#                note "CH SEND?";
                await $ch-ready;
#                note "CH SENDING";
                my $st = now;
                for ^$count {
                    $channel.send: $_;
                    ++⚛$ch-write-count;
                }
#                note "ch-writer $sender done";
                my $et = now;
                cas $ch-write-total, { $_ + $et - $st }
            }
        }

        # Ignite the engines!
        $pc-ready.keep;
        $ch-ready.keep;
        await @ch-writers;

#        note "channel writers done";

        my $pc-writers-done;
        # Don't wait for PChannel writer longer that 10 times of that of Channel writers.
        await Promise.anyof(
            Promise.allof(|@pc-writers).then({ $pc-writers-done //= True }),
            Promise.in($ch-write-total * 100).then({ $pc-writers-done //= False }),
        );
#        bail-out "Takes too long for writers to complete" unless $pc-writers-done;

#        note "pchannel writers done";

        is $ch-write-count, $expected, "sent the expected number of items over Channel";
        is $pc-write-count, $expected, "sent the expected number of items over PChannel";

        if $with-close {
            $pchannel.close;
            $channel.close;
        }
        else {
            for ^$receivers {
#                note "SENDING Nil to receiver ", $_, " of ", $receivers;
                $pchannel.send: Nil, 0;
                $channel.send: Nil;
            }
        }

        diag "All items ($pc-write-count) were sent" if $report-progress;
        # note "Channel  send: ", $ch-write-total;
        # note "PChannel send: ", $pc-write-total;

        await @ch-readers;

#        note "channel readers done, total time: ", $ch-read-total, ", max for pchannel: ", $ch-read-total * 15;

        my $pc-readers-done;
        await Promise.anyof(
            Promise.allof(|@pc-readers).then({ $pc-readers-done //= True }),
            Promise.in($ch-read-total * 20).then({ $pc-readers-done //= False }),
            );
        ok $pc-readers-done, "all PChannel readers are done";
        diag "Unread elems left: ", $pchannel.elems unless $pc-readers-done;

#        note "pchannel readers done";

        is $pc-read-count, $expected, "all items sent over PChannel were received";
        is $ch-read-count, $expected, "control: all items sent over Channel were recived";

        my $write-ratio = $pc-write-total / $ch-write-total;
        diag "Send   : ", $write-ratio.fmt('%.2f'), " times slower for PChannel" if $on-terminal;

        my $read-ratio = $pc-read-total / $ch-read-total;
        diag "Receive: ", $read-ratio.fmt('%.2f'), " times slower for PChannel" if $on-terminal;
    }
}

my $default-workers = %*ENV<ROBUST_WORKERS> || $*KERNEL.cpu-cores;
my $count = %*ENV<ROBUST_ITEM_COUNT> || 10000;
my $prios = %*ENV<ROBUST_PRIOS> || 1000;
my $senders = $default-workers;
my $receivers = $default-workers;
my $expected = $senders * $count;

test-robust "Many senders, many receivers",   :$count, :$prios, :$senders, :$receivers;
test-robust "Many senders, many receivers, no closing",   :$count, :$prios, :$senders, :$receivers, :!with-close;
test-robust "Single sender, many receivers",  :$count, :$prios, :senders(1), :$receivers;
test-robust "Single sender, many receivers, no closing",  :$count, :$prios, :senders(1), :$receivers, :!with-close;
test-robust "Many senders, single receiver",  :count(($count / $senders).Int), :$prios, :$senders, :receivers(1);
test-robust "Many senders, single receiver, no closing",  :count(($count / $senders).Int), :$prios, :$senders, :receivers(1), :!with-close;
test-robust "Single sender, single receiver", :$count, :$prios, :senders(1), :receivers(1);
test-robust "Single sender, single receiver, no closing", :$count, :$prios, :senders(1), :receivers(1), :!with-close;

done-testing;
