# Design

For a more in-depth explanation, see PROTOCOL.md.

신경 tries to be stupidly easy to run - outside of port, password, and
clustering, there isn't any configuration. In line with this goal is the fact
that 신경 does not require using a custom binary protocol, raw TCP/UDP sockets,
or similar. A very explicit goal of 신경 is that **anything** that speaks
websockets can speak the 신경 protocol. This allows for things like a
monitoring/web panel to just be another 신경 client, rather than something that
might need to be specially baked in. Additionally, this means that 신경 is
designed for clients to appear and disappear randomly. 

One of the main "points" of 신경 is that all communication is expected to be
run over it; it is NOT expected that a client can discover another client's 
IP + port or similar. All messages, HTTP requests, ... for 신경-connected 
services should be done entirely over 신경.

Additionally, 신경 pushes a significant amount of responsibility on clients, to
allow for some functionality to work in a "nice" way. This is explained in the
relevant sections.

## Connection lifecycle

The 신경 connection lifecycle is heavily inspired by the 
[Discord](https://discord.com) gateway (plz don't sue me ;;). The gist of it is

- Open a websocket connection to the server
- Receive a "hello" payload, telling the client how often it needs to heartbeat
- Identify the client, which includes data such as
  - What application is this client a part of?
  - What is the client's id?
  - What tags is the client identifying itself with?
  - Is the client reconnecting? If yes, allow it to reuse app name/id 
    combinations, **if and only if** the client is not restricted.
  - Sending the password to authenticate with. The password must **exactly**
    match what the server has configured as a password! That is, if the server
    does not have a password configured, the client must **not** send a 
    password.
- Receive a "ready" payload, indicating that the server has finished with 
  initial processing and is ready for the client to start sending/recving. any
  messages / HTTP requests / similar.
- The client must periodically send a heartbeat payload to keep its connection 
  alive; failure to do so will result in disconnection. Additionally, a client
  that does not heartbeat but does still send other messages will be 
  disconnected **without warning** if too much time has passed between
  heartbeats. When this happens, a payload will be sent to the client 
  indicating why it was disconnected.

## Metadata and routing

Clients that connect to 신경 all inherently have a few metadata values that 
**cannot** be set by clients. Specifically, `ip`, `restricted`, and 
`last_heartbeat_time` **cannot** be set by clients, under *any* circumstances.
This is because these metadata keys are used internally for a number of things
(ex. denying messages to restricted-mode clients); this information is stored 
as metadata values so that they can easily be queried just like any other 
metadata value stored in 신경.

신경 stores metadata in Mnesia. This is so that 신경 can take advantage of the
speed of keeping everything in-memory while still having flexible data 
querying.

All messages / proxied HTTP requests are effectively random-routed. This was
because "implement proper round-robin" was a surprisingly hard task while still
meeting some of the goals 신경 has. Specifically, storing even more state about
what clients were last communicated with for round-robin was somewhat at-odds
with having the goal that clients can randomly appear/disappear at any time.
Maybe someday I'll add a real solution for this (or someone could PR it...),
but for now it's all random-routing.

For more information about Mnesia, see the following links:

- http://erlang.org/doc/man/mnesia.html
- https://en.wikipedia.org/wiki/Mnesia

### Metadata queries

신경 uses metadata queries to determine how to route messages / requests 
around. A description of how it works can be found in PROTOCOL.md, but suffice
to say, 신경 queries follow a MongoDB-inspired syntax. Metadata queries are the
fundamental thing that lets 신경 work. Fundamentally though, metadata queries
are very simple. 

### Reconnects

When a client is disconnected from 신경, *its metadata is wiped from the store*,
barring any unusual circumstances. As such, when a client reconnects, it is
**required** that said client immediately pushes its cached metadata back to
the server when it has reached the "ready" point of its lifecycle. This is 
admittedly an odd choice. The reason for doing this is that we can keep the
신경 node itself stateless, and roll restarts of a 신경 cluster with near-zero
"downtime."

## Service discovery

신경 allows services to register "tags" to describe themselves when they send
an identify payload. These tags can later be used to discover services. For 
example:

Suppose two services: `api` and `expensive`, where the latter of the two is 
some computationally-expensive thing. If, for some reason, the `api` service
does not know the name of the `expensive` service, it can run a "query" to 
discover the names of services describing themselves as 
`computationally-expensive`.

Admittedly this is a somewhat-contrived example, but it should illustrate how
신경 service discovery works.

### Dynamic metadata query targets

Metadata queries benefit from this same service discovery mechanism. Rather
than having to hardcode application names into queries, services can instead
set the "target" of a query to an array of tags, and 신경 will automatically
use those tags to discover a suitable target service before handling the 
"request."