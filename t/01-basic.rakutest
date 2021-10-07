use v6.c;
use Test::Async;
use Concurrent::PChannel;

plan 3;

subtest "Errors" => {
    plan 6;

    throws-like
        { Concurrent::PChannel.new(:priorities(0)) },
        X::PChannel::Priorities,
        "constructor with wrong priorities throws X::PChannel::Priorities",
        :priorities(0);

    my $pchannel = Concurrent::PChannel.new;

    throws-like
        { $pchannel.send: 42, -42 },
        X::PChannel::NegativePriority,
        "use of negative priority throws X::PChannel::NegativePriority",
        :prio(-42);

    lives-ok { $pchannel.close }, "single close is fine";

    throws-like
        { $pchannel.send(42, 0) },
        X::PChannel::OpOnClosed,
        "send on closed throws X::PChannel::OpOnClosed",
        :op('send');

    fails-like
        { $pchannel.receive },
        X::PChannel::OpOnClosed,
        "receive on close fails with X::PChannel::OpOnClosed",
        :op('receive');

    throws-like
        { $pchannel.close },
        X::PChannel::OpOnClosed,
        "second close throws X::PChannel::OpOnClosed",
        :op('close');
}

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
