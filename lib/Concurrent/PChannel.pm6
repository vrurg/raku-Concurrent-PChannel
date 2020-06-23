use v6.c;
unit class Concurrent::PChannel:ver<0.0.2>:auth<github:vrurg>;

=begin pod

=head1 NAME

Concurrent::PChannel - prioritized channel

=head1 SYNOPSIS

=begin code :lang<perl6>

use Concurrent::PChannel;

my Concurrent::PChannel:D $pchannel .= new( :priorities(10) );
$pchannel.send("low prio", 0);
$pchannel.send("high prio", 1);
say $pchannel.receive; ‘high prio’
say $pchannel.receive; ‘low prio’

=end code

=head1 DESCRIPTION

C<Concurrent::PChannel> implements concurrent channel where each item sent over the channel has a priority attached
allowing items with higher priority to be pulled first from the channel even if they were sent later in time.

For example, imagine there is a factory of devices supplying our input with different kind of events. Some event types
are considered critical and must be processed ASAP. And some are, say, informative and can be taken care of when we're
idling. In code this could be implemented the following way:

=begin code :lang<perl6>
my $pchannel = Concurrent::PChannel.new( :priorities(3) );
for $dev-factory.devices -> $dev {
    start {
        react {
            whenever $dev.event-supply -> $event {
                given $event.type {
                    when EvCritical {
                        $pchannel.send: $event, 2;
                    }
                    when EvInformative {
                        $pchannel.send: $event, 0;
                    }
                    default {
                        $pchannel.send: $event, 1;
                    }
                }
            }
        }
    }
}

for ^WORKER-COUNT {
    start {
        while $pchannel.receive -> $event {
            ...
        }
    }
}
=end code

=head2 Performance

The performance was the primary target of this module development. It is implemented using highly-concurrent lock-less
(with one little exception) approach. Benchmarking of sending items of 1000 different priorities shows that sending
speed is only 1.9-2.3 times slower than that of the built-in C<Channel> class; while receiving is only 1.2-1.3 times
slower comparing to C<Channel>.

What's more important, the speed is almost independant of the number of priorities used! I.e. it doesn't matter if code
is using 10 or 1000 priorities – the time needed to process the queue would only be dependent on the number of items
sent.

=head2 Terms

=head3 Closed And Drained

A channel could be in three different states: normal, closed, and drained. The difference between the last two is that
when the channel is closed it might still have some data available for receiving. Only when all items were consumed by
the user code then the channel transitions into the I<closed> and the I<drained> state.

=head3 Priority

Priority is a positive integer value with 0 being the lowest possible priority. The higher the value the sooner an item
with this priority will reach the consumer.

=head1 ATTRIBUTES

=head2 C<closed>

C<True> if channel has been closed.

=head2 C<closed-promise>

A C<Promise> which is kept with C<True> when the channel is closed and broken with a cause object if channel is marked
as failed.

=head2 C<drained>

C<True> if channel is closed and no items left to fetch.

=head2 C<drained-promise>

A C<Promise> which is kept with C<True> when the channel is drained.

=head2 C<elems>

Likely number of elements ready for fetch. It is I<"likely"> because in a concurrent environment this value might be
changing too often.

=head2 C<prio-count>

Number of priority queues pre-allocated.

=head1 METHODS

=head2 C<new>

C<new> can be used with any parameters. But usually it is recommended to specifiy C<:priorities(n)> named parameter to
specify the expected number of priorities to be used. This allows the class to pre-allocate all required priority queues
beforehand. Without this parameter a class instance starts with only one queue. If method C<send> is used with a
priority which doesn't have a queue assigned yet then the class starts allocating new ones by multiplying the number of
existing ones by 2 until get enough of them to cover the requested priority. For example:

=begin code :lang<perl6>
my $pchannel.new;
$pchannel.send(42, 5);
=end code

In this case before sending C<42> the class allocates 2 -> 4 -> 8 queues.

Queue allocation code is the only place where locking is used.

Use of C<priorities> parameter is recommended if some really big number of priorities is expected. This might help in
reducing the memory footprint of the code by preventing over-allocation of queues.

=head2 C<send(Mu \item, Int:D $priority = 0)>

Send a C<item> using C<$priority>. If C<$priority> is omitted then default 0 is used.

=head2 C<receive>

Receive an item from channel. If no data available and the channel is not I<drained> then the method C<await> for the next
item. In other words, it soft-blocks allowing the scheduler to reassing the thread onto another task if necessary until
some data is ready for pick up.

If the method is called on a I<drained> channel then it returns a C<Failure> wrapped around C<X::PChannel::OpOnClosed>
exception with its C<op> attribute set to string I<"receive">.

=head2 C<poll>

Non-blocking fetch of an item. Contrary to C<receive> doesn't wait for a missing item. Instead the method returns
C<Nil but NoData> typeobject. C<Concurrent::PChannel::NoData> is a dummy role which sole purpose is to indicate that
there is no item ready in a queue.

=head2 C<close>

Close a channel.

=head2 C<fail($cause)>

Marks a channel as I<failed> and sets failure cause to C<$cause>.

=head2 C<failed>

Returns C<True> if channel is marked as failed.

=head2 C<Supply>

Wraps C<receive> into a supplier.

=head1 EXCEPTIONS

Names is the documentation are given as the exception classes are exported.

=head2 C<X::PChannel::Priorities>

Thrown if wrong C<priorities> parameter passed to the method C<new>. Attribute C<priorities> contains the value passed.

=head2 C<X::PChannel::NegativePriority>

Thrown if a negative priority value has passed in from user code. Attribute C<prio> contains the value passed.

=head2 C<X::PChannel::OpOnClosed>

Thrown or passed in a C<Failure> when an operation is performed on a closed channel. Attribute C<op> contains the
operation name.

I<Note> that semantics of this exception is a bit different depending on the kind of operation attempted. For
C<receive> this exception is used when channel is I<drained>. For C<send>, C<close>, and C<fail> it is thrown right away
if channel is in I<closed> state.

=head1 AUTHOR

Vadim Belman <vrurg@cpan.org>

=head1 COPYRIGHT AND LICENSE

Copyright 2020 Vadim Belman

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod
use nqp;

role NoData is export {};

class X::PChannel::Priorities is Exception is export {
    has $.priorities is required;
    method message {
        "Number of priorities is expected to be 1 or more, got " ~ $!priorities
    }
}

class X::PChannel::NegativePriority is Exception is export {
    has $.prio is required;
    method message {
        "Priority must be a positive integer, but got '{ $!prio.raku }'"
    }
}

class X::PChannel::OpOnClosed is Exception is export {
    has Str:D $.op is required;
    method message {
        $!op ~ " on closed PChannel"
    }
}

my class PQueue is repr('ConcBlockingQueue') {}

# The channel has been closed. Yet, some data might still be awailable for fetching!
has Bool:D $.closed = False;
has Promise $.closed-promise .= new;
# The channel is closed and no more data left in it.
has Bool:D $.drained = False;
has Promise $.drained-promise .= new;

# Number of elements available in all priority queues; i.e. in the channel itself. Has limited meaning in concurrent
# environment.
has atomicint $.elems = 0;

# Receive is Awaiting Promise. To be kept by a send to indicate data readiness.
has Promise $!ra-promise = Nil;
# Promise to be stored into $!ra-promise when time comes.
has $!ra-new = Promise.new;
# State variable for receive() method spinlock()
has int $!ra-protect = 0;
#has Lock $!ra-lock .= new;

# Total number of priority queues allocated
has atomicint $.prio-count = 0;
# Number of the highest priority queue where it's very likely to find some data. This attribute is always updated when
# send receives a packet. A poll might set it to lower value if it finds an empty priority queue.
has $!max-sent-prio = -1;
# Number of the highest priority queue where we expect to find some data.
has int $!max-recv-prio = -1;
# List of priority queues. For performance matters, it must be a nqp::list()
has $!pq-list;
has Lock $!prio-lock .= new;

submethod TWEAK(Int:D :$priorities = 1, |) {
    X::PChannel::Priorities.new(:$priorities).throw unless $priorities > 0;
    $!pq-list := nqp::list();
    # Pre-create priorities.
    self!pqueue($priorities - 1);
}

# Must only be called if no priority queue is found for a specified priority. It pre-creates necessary entries in
# $!pq-list.
method !pqueue(Int:D $prio) is raw {
    $!prio-lock.protect: {
        until $prio < $!prio-count {
            my $new-count = $!prio-count * 2;
            nqp::while(
                nqp::isle_i($!prio-count, $new-count),
                nqp::stmts(
                    nqp::push($!pq-list, PQueue.new),
                    nqp::atomicinc_i($!prio-count)));
        }
    }
    nqp::atpos($!pq-list, $prio)
}

method !wake-receivers {
    loop {
        my $ra-promise = $!ra-promise;
        if cas($!ra-promise, $ra-promise, Promise) === $ra-promise {
            .keep with $ra-promise;
            return
        }
    }
}

method send(Mu \packet, Int:D $prio) {
    nqp::if(
        nqp::islt_i($prio, 0),
        X::PChannel::NegativePriority.new(:$prio).throw);
    nqp::if(
        $!closed,
        X::PChannel::OpOnClosed.new(:op<send>).throw);
    my $pq := nqp::atpos($!pq-list, $prio);
    nqp::if(
        nqp::unless(
            nqp::isge_i($prio, $!prio-count),
            nqp::isnull($pq)),
        ($pq := self!pqueue($prio)));
    my $entry-elems = $!elems⚛++;
    nqp::push($pq, packet);
    cas $!max-sent-prio, {
        nqp::if(nqp::isgt_i($prio, $!max-sent-prio), $prio, $_);
    }
    self!wake-receivers unless $entry-elems;
}

method close {
    if cas($!closed, False, True) {
        # Two concurrent closes? Not good.
        X::PChannel::OpOnClosed.new(:op<close>).throw;
    }
    $!closed-promise.keep;
    self!wake-receivers;
}

method !drain {
    unless cas($!drained, False, True) {
        $!drained-promise.keep;
    }
}

method failed {
    $!closed-promise.status ~~ Broken
}

# XXX Would need better handling for when promise is not broken
method cause {
    $!closed-promise.cause
}

method fail($cause) {
    if cas($!closed, False, True) {
        # Two concurrent closes? Not good.
        X::PChannel::OpOnClosed.new(:op<close>).throw;
    }
    $!closed-promise.break($cause);
}

method poll is raw {
    my $packet;
    my $found := False;
    my $elems;
    cas $!elems, { ($elems = $_) ?? $_ - 1 !! $_ };
    if $elems {
        # Even though we've been promised to have an item in a queue, it is possible that the item hasn't been pushed by
        # send() yet. So, loop until find it.
        until $found {
            # We iterate starting with the maximum priority where we expect to find available items. Then going down the
            # priorities queue looking for the first one which actually has any data for us. When done try updating the
            # $!max-recv-prio for the next poll() invocation.
            my $max-sent = $!max-sent-prio;
            cas($!max-sent-prio, $max-sent, 0);
            my $prio = (my $max-recv = cas($!max-recv-prio, {
                nqp::if(nqp::isgt_i($max-sent, $_), $max-sent, $_)
            })) + 1;
            nqp::while(nqp::if(nqp::not_i($found), (--$prio >= 0)), nqp::unless(
                nqp::isnull($packet := nqp::queuepoll(nqp::atpos($!pq-list, $prio))), ($found := True)));
            # Update $!max-sent-prio if need and can. We're ok to change it only if the original object we used to start# the scan with hasn't been changed by a concurrent send operation.
            nqp::if(nqp::islt_i($prio, $max-recv), cas($!max-recv-prio, $max-recv, $prio));
        }
    }
    elsif $!closed && !$!drained {
        self!drain;
    }
    $found ?? $packet !! (Nil but NoData)
}

method receive is raw {
    loop {
        if $!drained {
            fail X::PChannel::OpOnClosed.new(:op<receive>);
        }
        my $ra-promise;
        unless ⚛$!closed {
            LEAVE nqp::atomicstore_i($!ra-protect,0);
            my $done := 0;
            nqp::until(
                $done,
                nqp::unless(nqp::cas_i($!ra-protect,0,1), ($done := 1)));
#            $!ra-lock.lock;
#            LEAVE $!ra-lock.unlock;
            if (my $ra-prev = cas($!ra-promise, Promise, $!ra-new)) !=== Promise {
                $ra-promise = $ra-prev;
            }
            else {
                $ra-promise = $!ra-new;
                $!ra-new = Promise.new;
            }
        }
        if (my $packet := self.poll) ~~ NoData {
            unless ⚛$!closed {
                await Promise.anyof($ra-promise, $!drained-promise, $!closed-promise);
            }
        }
        else {
            return $packet;
        }
    }
}

method Supply {
    supply {
        loop {
            my $v = self.receive;
            if $v ~~ Failure && $v.exception ~~ X::PChannel::OpOnClosed {
                $v.so;
                done;
            }
            else {
                emit $v;
            }
        }
    }
}

has $!dumped = 0;
method !dump {
    my $od = $!dumped;
    if cas($!dumped, $od, 1) != 0 {
        return;
    }
    for ^$!prio-count -> $prio {
        my $pq := nqp::atpos($!pq-list, $prio);
        if nqp::elems($pq) {
            note "\nPQ $prio: ", nqp::elems($pq), " -- ", nqp::atpos($pq, 0);
        }
        else {
            $*ERR.print: " $prio"
        }
    }
}
