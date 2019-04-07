# 신경

Singyeong (신경) is the nerve-center of your microservices-based application,
providing a metadata-oriented message bus for IPC, service discovery, dynamic
request proxying, and more. 신경 aims to be simple to use, but still provide
powerful features.

For a high-level overview of how 신경 works, check out DESIGN.md.

신경 can be discussed in the amyware Discord server: https://discord.gg/aJSRXdd

### Clients:

Language | Link
---------|-----
Java     | https://github.com/queer/singyeong-java-client

### Credit

신경 was **heavily** inspired by the [Ayana](https://ayana.io/) developers who
are implementing something similar with [Sekitsui](https://gitlab.com/sekitsui).
신경 exists because it has somewhat-different goals than Sekitsui. 

## WARNING

신경 is **ALPHA-QUALITY** software. The core functionality works, but there's
no guarantee that it won't break, eat your cat, ... Use at your own risk!

## Configuration

Configuration is done via environment variables.

```Bash
# The port to bind to. Default is 4000. In production, you probably want to be
# running on port 80.
PORT="4567"

# The password that clients must send in order to connect. Optional.
# It is HIGHLY recommended that you set a long / complex password. See the
# "Security" section below for more on why. 
AUTH="2d1e29fbe6895b3693112ff<insert more long password here>"

# Whether or not clustering should be enabled.
CLUSTERING="true"
# The cookie is used for securing communication between nodes. See 
# http://erlang.org/doc/reference_manual/distributed.html §13.7 Security.
COOKIE="very long and secure cookie that nobody can guess"
# Everything needed to connect to Redis. 신경 uses Redis for cluster member
# discovery.
REDIS_DSN="redis://:password@127.0.0.1:6379/0"
```

## Clustering

신경 is capable of bootstrapping the Erlang node and discovering cluster
members automatically; you do ***not*** need to manually set the Erlang
distribution flags, and *you should not set them*. 신경 will set everything up
automatically.

신경 uses Redis for discovering cluster members. There might be more options
supported eventually.

Someday it might be cool to support gossip protocol, kube api, ... to allow for
automatically forming clusters w/o external dependencies, I guess.

## What exactly is it?

신경 is a metadata-oriented service mesh. Clients connect over a websocket
(protocol defined in PROTOCOL.md), and can send messages that can be routed to
clients based on client metadata.

### Metadata-oriented?

신경 clients are identified by three factors:

1. Application id.
2. Client id.
3. Client metadata.

When sending messages or HTTP requests over 신경, you do not choose a target
service instance directly, nor does 신경 choose for you. Rather, you specify a
target application and a metadata query. 신경 will then run this query on all
clients under the given application, and choose one that matches to receive the
message or request.

For example, suppose you wanted to let users who had opted-in to a beta program
use beta features, but not all users. You could express this as a 신경 query,
and say something like "send this message to some service in the `backend`
application where `version_number >= 2.0.0`."

Of course, something like that is easy, but 신경 lets you do all sorts of 
things easily. For example, suppose you had a cluster of websocket gateways
that users connected to and received events over. Instead of having to know
which gateway a user is connected to, you could trivially express this as a 
신경 query - "send this message to a `gateway` node that has `123` in its 
`connected_users` metadata." Importantly, **sending messages like this is done
in exactly the same way as sending any other message.** 신경 tries to make it 
very easy to express potentially-complicated routing with the same syntax as a 
simple "send to any one service in this application group."

### Do I need to know exact client IDs to send messages?

No. You should not try to route to a specific 신경 client by id; instead you 
should be expressing a metadata query that will send to the client you want.

### Do I need to hard-code application IDs?

No. When clients connect to 신경, they can choose to set some tags describing 
WHAT they are; consumers of 신경 can then use the HTTP API to discover service
names based on tags. Check out the "Service discovery" section in DESIGN.md for
more. 

### Do I need sidecar containers if I'm running in Kubernetes?

Nope.

### Does it support clustering / multi-master / ...?

No. Hopefully someday.

## Why should I use this?

- No need for Kubernetes or something similar - anything that can speak
  websockets is a valid 신경 client. 
- No configuration. 신경 is meant to be "drop in and get started" - a few 
  options exist for things like authentication, but beyond that, no 
  configuration should be needed (at least to start out).
- Fully dynamic. 신경 is meant to work well with clients randomly appearing and
  disappearing (ex. browser clients when using 신경 as a websocket gateway).
- No sidecars.
- Choose where messages / requests are routed at runtime; no need to bake exact
  targets into your application.
- Service discovery without DNS.
- Service discovery integrated into HTTP proxying / message sending.

## Why should I NOT use this?

- Query performance might be unacceptable.
- Websockets might not be acceptable.
- Lack of clustering support (See issue #4).
- JSON parsing might be too high (See issue #2).

## Why make this?

I write [Discord](https://discordapp.com/) bots. With how Discord bot 
[sharding](https://discordapp.com/developers/docs/topics/gateway#sharding)
works, it's INCREDIBLY convenient to be able to say "send this message to the
shard for guild id 1234567890" rather than having to figure out which shard id
that guild is on, figure out which container it's in (when running shards in a
distributed manner), ... Not having to pay the price of doing a broadcast to 
all containers for an application type is also beneficial. This extends to 
other services that handle things on a per-guild basis, ex. having a cluster of
voice nodes, where not needing to know which node holds a particular guild is
very useful.

Additionally, being able to discover-by-tags is VERY useful - I don't have to 
know ANYTHING about the receiving end other than what tags it might use for 
itself! I can say things like "send this message to the service that describes
itself as 'image-generator' and 'prod' with `latency < 100ms`," and 신경 will
figure out how to get it where it needs to go.

### Why Elixir? Why not Go, Rust, Java, ...?

I like Elixir :thumbsup: I'm not amazing at it, but I like it.

### Why using Phoenix? Why not just use Cowboy directly?

Phoenix's socket abstraction is really really useful. Also I didn't want to 
have to build eg. HTTP routing from scratch; Phoenix does a great job of it
already so no need to reinvent the wheel. :meowupsidedown:

## How do I write my own client for it? How does it work internally? etc.

Check out PROTOCOL.md.

## How do I run the tests?

`mix test`. ~~Of course, there are no tests because I forgot to write
them. Oops.~~

I finally added tests. ~~Please clap~~ More will likely be added over time.

Note that the HTTP proxying tests use an echo server I wrote (`echo.amy.gg`),
rather than using a locally-hosted one. If you don't want to run these tests,
set the `DISABLE_PROXY_TESTS` env var.

## Security

Note that **there is no ratelimit on authentication attempts**. This means that
a malicious client can constantly open connections and attempt passwords until
it gets the correct one. It is **highly** recommended that you use a very long,
probably-very-complicated password in order to help protect against this sort
of attack.

## What is that name?

I have it on good authority (read: Google Translate) that 신경 means "nerve." I
considered naming this something like 등뼈 (deungppyeo, "spine"/"backbone") or 
회로망 (hoelomang, "network") or even 별자리 (byeoljali, "constellation), but I 
figured that 신경 would be easier for people who don't know Korean to 
pronounce, as well as being easier to find from GitHub search.

## Shameless plug

If you like what I make, consider supporting me on Patreon.

[![patreon button](https://i.imgur.com/YFjoCd1.png)](https://patreon.com/amyware)