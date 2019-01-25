# 신경

Singyeong (신경) is the nerve-center of your microservices-based application,
providing a metadata-oriented message bus for IPC, service discovery, dynamic
request proxying, and more.

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
# The port to bind to. Default is 4000. In production, you probably want to be
# running on port 4000.
PORT=4567
# The password that clients must send in order to connect. Optional.
# It is HIGHLY recommended that you set a long / complex password. See the
# "Security" section below for more on why. 
AUTH="2d1e29fbe6895b3693112ff<insert more long password here>"
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

### Do I need to hard-code application IDs?

No. When clients connect to 신경, they can choose to set some tags describing 
WHAT they are; consumers of 신경 can then use the HTTP API to discover service
names based on tags. Check out the "Service discovery" section in API.md for
more. 

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

Phoenix's socket abstraction is really really useful. Also I didn't want to 
have to build eg. HTTP routing from scratch; Phoenix does a great job of it
already so no need to reinvent the wheel. :meowupsidedown:

## How do I write my own client for it? How does it work internally? etc.

Check out NOTES.md.

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