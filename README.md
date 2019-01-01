# 신경

Singyeong (신경) is the nerve-center of your microservices-based application,
providing a metadata-oriented message bus for communication between services.

A (somewhat-untested) reference client can be found here: 
https://github.com/singyeong/java-client

Clients are stored under an org because I don't want them cluttering up my 
repos page. 

## WARNING

신경 is **ALPHA-QUALITY** software. The core functionality works, but there's
no guarantee that it won't break, eat your cat, ... Use at your own risk!

## Configuration

Configuration is done via environment variables.

```Bash
# The port to run the websocket gateway on
PORT=4567
# The password that clients must send in order to connect. Optional.
AUTH="2d1e29fbe6895b3693112ff"
```

## What exactly is it?

신경 is a metadata-oriented message bus of sorts. Clients connect over a 
websocket (protocol defined in NOTES.md), and can send messages that can be 
routed to clients based on client metadata.

### Metadata-oriented?

신경 does not allow you to send a message to a single client by id, or to what
other messages buses/queues would call a "topic," or etc. Rather, 신경 allows
clients to send metadata updates (which are stored on the server), and then
clients can send messages that are routed based on this metadata. For example,
you can say "this user is in beta, so send all messages related to them to the 
services with `version_number >= 2.0.0`," or "send this message to all services
of this type where `processing_latency < 100`," or so on. 

However, 신경 does NOT let you send messages directly to a client by id. If you
find that you need this functionality, you can get around it by just setting 
the client's id as a metadata key.

## Why?

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

### Why Elixir? Why not Go, Rust, Java, ...?

I like Elixir :thumbsup: I'm not amazing at it, but I like it :thumbsup:

### Why using Phoenix? Why not just use Cowboy directly?

Phoenix's socket abstraction is really really useful.

## How do I write my own client for it? How does it work internally? etc.

Check out NOTES.md.

## How do I run the tests?

`mix test`. ~~Of course, there are no tests because I forgot to write
them. Oops.~~

I finally added tests. ~~Please clap~~ More will likely be added over time.

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