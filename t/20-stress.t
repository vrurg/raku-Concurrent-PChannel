use Test::Async <When Base>;
use Concurrent::PChannel;

BEGIN {
    %*ENV<RAKUDO_MAX_THREADS> = 1500;
}

$*SCHEDULER = ThreadPoolScheduler.new;

my $conc-count = 1000;
my $prios = 10;
my $packet-count = 10000;

plan $conc-count, :parallel;

my $starter = Promise.new;

for ^$conc-count -> $id {
    subtest "Try $id", -> $suite {
        await $starter;
        my $q = Concurrent::PChannel.new( :priorities($prios) );
        start {
            for ^$packet-count -> $pkt-id {
                $q.send: $pkt-id, $prios.rand.Int;
            }
            $q.send: Nil, 0;
        }
        my atomicint $read-count = 0;
        loop {
            my $v = $q.receive;
            last unless $v ~~ Int;
            ++⚛$read-count;
        }
        is $read-count, $packet-count, "all $packet-count received";
    }
}

$starter.keep(True);

done-testing;
