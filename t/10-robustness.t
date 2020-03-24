use v6.c;
use Test;
use Concurrent::PChannel;

plan 4;

my $cpu-cores = $*KERNEL.cpu-cores;
my $count = 100000;
my $prios = 1000;
my $senders = $cpu-cores;
my $receivers = $cpu-cores;
my $expected = $senders * $count;

my $pchannel = Concurrent::PChannel.new: :priorities($prios);
my $pc-ready = Promise.new;
my $pc-read = Promise.new;
my $channel = Channel.new;
my $ch-ready = Promise.new;

my $pc-read-total = 0;
my $ch-read-total = 0;

my atomicint $pc-read-count = 0;
my atomicint $ch-read-count = 0;
my @pc-readers;
my @ch-readers;
for ^$receivers -> $rn {
    @pc-readers.push: start {
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
        await $pc-ready;
        my $st = now;
        for ^$count {
            $pchannel.send: ($sender * $count + $_), $prios.rand.Int; # ($v mod $prios);
            ++⚛$pc-write-count;
        }
        my $et = now;
        cas $pc-write-total, { $_ + $et - $st }
    }
    @ch-writers.push: start {
        await $ch-ready;
        my $st = now;
        for ^$count {
            $channel.send: $_;
        }
        my $et = now;
        cas $ch-write-total, { $_ + $et - $st }
    }
}

# Ignite the engines!
$pc-ready.keep(True);
$ch-ready.keep(True);
await @ch-writers;

my $pc-writers-done;
# Don't wait for PChannel writer longer that 10 times of that of Channel writers.
await Promise.anyof(
    Promise.allof(|@pc-writers).then({ $pc-writers-done //= True  }),
    Promise.in($ch-write-total * 10).then({ $pc-writers-done //= False }),
);
bail-out "Takes too long for writers to complete" unless $pc-writers-done;

is $pc-write-count, $expected, "sent the expected number of items";

$pchannel.close;
$channel.close;

my $write-ratio = $pc-write-total / $ch-write-total;
ok ($write-ratio < 10), "send is not too slow comparing to Channel send (" ~ $write-ratio.fmt("%.2f") ~ " times slower)";
# note "Channel  send: ", $ch-write-total;
# note "PChannel send: ", $pc-write-total;

await @ch-readers;

my $pc-readers-done;
await Promise.anyof(
    Promise.allof(|@pc-readers).then({ $pc-readers-done //= True  }),
    Promise.in($ch-read-total * 10).then({ $pc-readers-done //= False }),
);
bail-out "Takes too long for readers to complete" unless $pc-readers-done;

my $read-ratio = $pc-read-total / $ch-read-total;
ok ($read-ratio < 10), "receive is not too slow comparing to Channel receive (" ~ $read-ratio.fmt("%.2f") ~ " times slower)";

is $pc-read-count, $expected, "all items sent were received";

# note "Channel  recv: ", $ch-read-total;
# note "PChannel recv: ", $pc-read-total, ", count: ", $pc-read-count;
# note "";
# note "Send ratio: ", $pc-write-total / $ch-write-total;
# note "Recv ratio: ", $pc-read-total / $ch-read-total;

done-testing;
