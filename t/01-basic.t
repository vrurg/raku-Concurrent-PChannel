use v6.c;
use Test;
use Concurrent::PChannel;

plan 2;

subtest "Count messages" => {
    plan 3;
    my $pc = Concurrent::PChannel.new;

    my atomicint $counter = 0;
    my $closed-promise-fired = False;
    my $drained-promise-fired = False;

    $pc.closed-promise.then: {
        $closed-promise-fired = True;
    };
    $pc.drained-promise.then: {
        $drained-promise-fired = True;
    };

    # start readers
    my @rp;
    for ^10 {
        @rp.push: start {
            my $done;
            until $done {
                my $v = $pc.receive;
                if $v ~~ Failure {
                    $v.so;
                    $done = True;
                }
                else {
                    ++⚛$counter;
                }
            }
        }
    }

    my @sp;
    for ^10 -> $prio {
        @sp.push: start {
            for ^10 -> $val {
                $pc.send: $prio * 10 + $val, $prio;
            }
        }
    }
    await @sp;
    $pc.close;
    await @rp;

    is $counter, 100, "all packets passed";
    ok $closed-promise-fired, "close event results in kept promise";
    ok $drained-promise-fired, "draining results in kept promise";
}

# See if sending concurrently with different priorities we eventually get data in the orider of higher -> lower priority
# and the sending order withing priority is preserved.
subtest "Ordering" => {
    plan 3;

    my $count = 1000;
    my $pc = Concurrent::PChannel.new;
    my @prio-ready = Promise.new xx 3;

    my @p;
    for ^3 -> $prio {
        @p.push: start {
            for ^$count -> $val {
                $pc.send: $prio × $count + $val, $prio;
            }
            @prio-ready[$prio].keep(True);
        }
    }

    @p.push: start {
        for 2...0 -> $prio {
            await @prio-ready[$prio];
            my @list;
            for ^$count {
                @list.push: $pc.receive;
            }
            is-deeply @list, (^$count).map( * + $prio × $count ).Array, "prio $prio came in the order";
        }
    }

    await @p;
}

done-testing;
