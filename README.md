[![Build Status](https://travis-ci.org/vrurg/raku-Concurrent-PChannel.svg?branch=master)](https://travis-ci.org/vrurg/raku-Concurrent-PChannel)

NAME
====

Concurrent::PChannel - prioritized channel

SYNOPSIS
========

```perl6
use Concurrent::PChannel;

my Concurrent::PChannel:D $pchannel .= new( :priorities(10) );
$pchannel.send("low prio", 0);
$pchannel.send("high prio", 1);
say $pchannel.receive; ‘high prio’
say $pchannel.receive; ‘low prio’
```

DESCRIPTION
===========

`Concurrent::PChannel` implements concurrent channel where each item sent over the channel has a priority attached allowing items with higher priority to be pulled first from the channel even if they were sent later in time.

For example, imagine there is a factory of devices supplying our input with different kind of events. Some event types are considered critical and must be processed ASAP. And some are, say, informative and can be taken care of when we're idling. In code this could be implemented the following way:

```perl6
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
```

Performance
-----------

The performance was the primary target of this module development. It is implemented using highly-concurrent almost lock-less approach. Benchmarking of different numbers of sending/receiving threads (measured over `receive()` method) results in send operations been 1.3-8 times slower than sending over the core `Channel`; receiving is 1.1-6 times slower. The difference in numbers is only determined by the ratio of sending/receving threads.

What's more important, the speed is almost independent of the number of priorities used! I.e. it doesn't matter if code is using 10 or 1000 priorities – the time needed to process the two channels would only be dependent on the number of items sent over them.

Terms
-----

### Closed And Drained

A channel could be in three different states: normal, closed, and drained. The difference between the last two is that when the channel is closed it might still have some data available for receiving. Only when all items were consumed by the user code then the channel transitions into the *closed* and the *drained* state.

### Priority

Priority is a positive integer value with 0 being the lowest possible priority. The higher the value the sooner an item with this priority will reach the consumer.

ATTRIBUTES
==========

`closed`
--------

`True` if channel has been closed.

`closed-promise`
----------------

A `Promise` which is kept with `True` when the channel is closed and broken with a cause object if channel is marked as failed.

`drained`
---------

`True` if channel is closed and no items left to fetch.

`drained-promise`
-----------------

A `Promise` which is kept with `True` when the channel is drained.

`elems`
-------

Likely number of elements ready for fetch. It is *"likely"* because in a concurrent environment this value might be changing too often.

`prio-count`
------------

Number of priority queues pre-allocated.

METHODS
=======

`new`
-----

`new` can be used with any parameters. But usually it is recommended to specifiy `:priorities(n)` named parameter to specify the expected number of priorities to be used. This allows the class to pre-allocate all required priority queues beforehand. Without this parameter a class instance starts with only one queue. If method `send` is used with a priority which doesn't have a queue assigned yet then the class starts allocating new ones by multiplying the number of existing ones by 2 until get enough of them to cover the requested priority. For example:

```perl6
my $pchannel.new;
$pchannel.send(42, 5);
```

In this case before sending `42` the class allocates 2 -> 4 -> 8 queues.

Queue allocation code is the only place where locking is used.

Use of `priorities` parameter is recommended if some really big number of priorities is expected. This might help in reducing the memory footprint of the code by preventing over-allocation of queues.

`send(Mu \item, Int:D $priority = 0)`
-------------------------------------

Send a `item` using `$priority`. If `$priority` is omitted then default 0 is used.

`receive`
---------

Receive an item from channel. If no data available and the channel is not *drained* then the method `await` for the next item. In other words, it soft-blocks allowing the scheduler to reassing the thread onto another task if necessary until some data is ready for pick up.

If the method is called on a *drained* channel then it returns a `Failure` wrapped around `X::PChannel::OpOnClosed` exception with its `op` attribute set to string *"receive"*.

`poll`
------

Non-blocking fetch of an item. Contrary to `receive` doesn't wait for a missing item. Instead the method returns `Nil but NoData` typeobject. `Concurrent::PChannel::NoData` is a dummy role which sole purpose is to indicate that there is no item ready in a queue.

`close`
-------

Close a channel.

`fail($cause)`
--------------

Marks a channel as *failed* and sets failure cause to `$cause`.

`failed`
--------

Returns `True` if channel is marked as failed.

`Supply`
--------

Wraps `receive` into a supplier.

EXCEPTIONS
==========

Names is the documentation are given as the exception classes are exported.

`X::PChannel::Priorities`
-------------------------

Thrown if wrong `priorities` parameter passed to the method `new`. Attribute `priorities` contains the value passed.

`X::PChannel::NegativePriority`
-------------------------------

Thrown if a negative priority value has passed in from user code. Attribute `prio` contains the value passed.

`X::PChannel::OpOnClosed`
-------------------------

Thrown or passed in a `Failure` when an operation is performed on a closed channel. Attribute `op` contains the operation name.

*Note* that semantics of this exception is a bit different depending on the kind of operation attempted. For `receive` this exception is used when channel is *drained*. For `send`, `close`, and `fail` it is thrown right away if channel is in *closed* state.

AUTHOR
======

Vadim Belman <vrurg@cpan.org>

COPYRIGHT AND LICENSE
=====================

Copyright 2020 Vadim Belman

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

