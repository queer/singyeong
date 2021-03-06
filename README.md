# 신경

![Build status](https://github.com/queer/singyeong/workflows/Publish%20Docker/badge.svg) [![codecov](https://codecov.io/gh/queer/singyeong/branch/master/graph/badge.svg)](https://codecov.io/gh/queer/singyeong) [![Docker Hub](https://img.shields.io/badge/Docker%20Hub-queer%2Fsingyeong-%23007ec6)](https://hub.docker.com/r/queer/singyeong/tags) [![Dependabot Status](https://api.dependabot.com/badges/status?host=github&repo=queer/singyeong)](https://dependabot.com)

> ## 신경
> [/ɕʰinɡjʌ̹ŋ/ • sin-gyeong](https://en.wiktionary.org/wiki/%EC%8B%A0%EA%B2%BD#Pronunciation) <sup><sup>(try it with [IPA Reader](http://ipa-reader.xyz))</sup></sup>
> 1. nerve
>
> ## Nerve
> /nərv/ • *noun*
> 1. (in the body) a whitish fiber or bundle of fibers that transmits impulses of sensation to the brain or spinal cord, and impulses from these to the muscles and organs.
> 
> <small style="color:grey;">"the optic nerve"</small>

신경 is the nerve-center of your microservices, providing a message bus + message
queue with powerful routing, automatic load-balancing + failover, powerful HTTP
request proxying + routing, and more. 신경 aims to be simple to get started with
while still providing the features for a variety of use-cases.

신경 is a part of the [amyware Discord server](https://discord.gg/aJSRXdd).

If you like what I make, consider supporting me on Patreon:

[<img src="https://i.imgur.com/YFjoCd1.png" width="162" height="38" />](https://patreon.com/amyware)

### Clients:

Language   | Author                                             | Link                                              | Maintained?
-----------|----------------------------------------------------|---------------------------------------------------|-------------
Elixir     | [@queer](https://queer.gg)                         | https://github.com/queer/singyeong-client-elixir  | yes
.NET       | [@FiniteReality](https://github.com/FiniteReality) | https://github.com/finitereality/singyeong.net    | yes
Python     | [@PanKlipcio](https://github.com/PanKlipcio)       | https://github.com/StartITBot/singyeong.py        | yes
Typescript | [@cyyynthia](https://github.com/cyyynthia)         | https://github.com/borkenware/singyeongjs         | looks like yes (used in [squirrelchat](https://github.com/squirrelchat/squirrel)?)

#### Unmaintained clients

Language   | Author                                             | Link                                              | Notes
-----------|----------------------------------------------------|---------------------------------------------------|------------------------------------
Python     | [@PendragonLore](https://github.com/PendragonLore) | https://github.com/PendragonLore/shinkei          | Owner said it's unmaintained
Java       | [@queer](https://queer.gg)                         | https://github.com/queer/singyeong-java-client    | I don't write much Java anymore S:
Typescript | [@alula](https://github.com/alula)                 | https://github.com/KyokoBot/node-singyeong-client | Repo gone

### Credit

신경 was inspired by [sekitsui](https://gitlab.com/sekitsui), a project by the
[Ayana](https://ayana.io) developers. 신경 was developed due to sekitsui
seemingly having halted development (no release as far as I'm aware, no repo
activity in the last 1-2 years).

## WARNING

신경 is **ALPHA-QUALITY** software. The core functionality works, but there's
no guarantee that it won't break, eat your cat, ... Use at your own risk!

## Configuration

Configuration is done via environment variables, or via a custom configuration
file. See [`config.exs`](https://github.com/queer/singyeong/blob/master/config/config.exs)
for more information about config options.

### Custom config files

Sometimes, it's necessary to include custom configuration files - such as for
something that the environment variables don't cover. In such a case, you can
add a `custom.exs` file to `config/` that includes the custom configuration you
want / need.

Example: Prove that custom config works:
```Elixir
use Mix.Config

IO.puts "Loading some cool custom config :blobcatcooljazz:"
```

Example: Always have debug-level logging, even in prod mode:
```Elixir
use Mix.Config

config :logger, level: :debug
```

## Plugins

Plugins belong in a directory named `plugins` at the root directory. See the
[plugin API](https://github.com/queer/singyeong_plugin) and the
[example plugin](https://github.com/queer/singyeong-test-plugin) for more info.

## Clustering

신경 is capable of discovering cluster members automatically, using libcluster
and the gossip strategy by default.

## What exactly is it?

신경 is a metadata-oriented message bus + message queue + HTTP proxy. Clients
connect over a [websocket](https://github.com/queer/singyeong/blob/master/PROTOCOL.md),
and can send messages, queue messages, and send HTTP requests that can be
routed to clients based on client metadata.

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
Generally speaking, clients should be capable of running statelessly, or you
should use metadata to route messages effectively.

### Do I need sidecar containers if I'm running in Kubernetes?

Nope.

### Does it support clustering / multi-master / ...?

신경 has masterless clustering support.

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
- Development is still fairly early-stage; the alpha-ish quality of it may be
  nonviable.

## Why make this?

Metadata-based routing is useful for all sorts of things:

- Storing documentation about what messages your services send/recv, what REST
  endpoints they expose, ... and querying on it to route to a service that
  accepts a specific format of a specific message.
- Sending a message to a subset of clients without doing a full pubsub and
  relying on clients to drop them properly.
- [Discord](https://discord.com) bot message-passing between services. No more
  pubsub or whatever, just "send this message to the service where
  `123 in guild_ids`."
- Websocket gateway. "Send this message to the client where `user_id = 123`."
- [Container scheduling](https://github.com/queer/pig).
- [Monitoring host stats](https://github.com/queer/agma).
- Routing messages to an audit-logging service and a handler service at the
  same time.
- Message queues that can only dispatch messages when a client is capable (ex.
  "dispatch this message from the queue to a client where `latency < 10`")
- Anything you can think of!

In general, 신경 can get messages to the right place with some very complicated
conditions very easily.

### Why Elixir? Why not Go, Rust, Java, ...?

I like Elixir :thumbsup: Elixir is well-suited to the use-case of
message-queuing, and imo is a lot friendlier to write scalable messaging code
in with little effort relative to any of the above-mentioned languages.

### Why using Phoenix? Why not just use Cowboy directly?

Phoenix's socket abstraction is really really useful. Also I didn't want to
have to build eg. HTTP routing from scratch; Phoenix does a great job of it
already so no need to reinvent the wheel. While it is possible to use Plug or a
similar library on top of Cowboy or another HTTP server, I just liked the
convenience of getting it all out-of-the-box with Phoenix and being able to
focus on writing my application-level code instead of setting up a ton of weird
plumbing.

## How do I write my own client for it?

Check out [PROTOCOL.md](https://github.com/queer/singyeong/blob/master/PROTOCOL.md).

## How does it work internally?

The code is intended to be pretty easy to read. The general direction that data
flows is something like:

```
client -> decoder -> gateway -> dispatch         -> process and dispatch response
                             -> identifier       -> allow or reject connection
                             -> metadata updater -> apply or reject metadata updates
```

In terms of module structure, the way things go is something like:

```
|-> <phx/cowboy code>
|           |
|           V
|   SingyeongWeb.Transport.Raw
|           |
|           V
|   Singyeong.Gateway
|           |
|           |------------------------------------|-----------------------------------------|
|           V                                    V                                         V
|   Singyeong.Gateway.Handler.Identify   Singyeong.Gateway.Handler.DispatchEvent   Singyeong.Gateway.Handler.Heartbeat
|           |                                    |                                         |
|           V                                    V                                         V
|   Singyeong.Gateway                    Singyeong.Gateway.Dispatch                Singyeong.Store ---------|
|           |                                    |                                                          |
|           V                     |--------------|-----------------|-----------------------------|          |
|-- SingyeongWeb.Transport.Raw    |              V                 |                             |          |
            ^                     V      (METADATA_UPDATE)         V                             V          |
            |        Singyeong.Gateway   Singyeong.Store   Singyeong.MessageDispatcher   Singyeong.Queue    |
            |----------------|                                     |                             |          |
            |                                                      |                             |          |
            |------------------------------------------------------|-----------------------------|----------|
```

Additionally, I aim to keep the server fairly small, ideally <5k LoC, but
absolutely <10kLoC no matter what.. At the time of writing, the server is
~3.600 LoC:

```
git:(master) X | ->  tokei lib/
===============================================================================
 Language            Files        Lines         Code     Comments       Blanks
===============================================================================
 Elixir                 48         4558         3621          267          670
===============================================================================
 Total                  48         4558         3621          267          670
===============================================================================
git:(master) X | ->
```

### How does querying / messaging work?

When you send a message, the server inspects its target (ie. its metadata
query) and queries its own internal metadata store to find clients that can be
routed to that match said query. In the case of a multi-node setup, each node
is only aware of its own clients, and thus metadata queries are a parallel RPC
across the cluster.

A very basic query looks like this:

```javascript
{
  "application": "api",
  "ops": [],
}
```

That is, "route this message to any client that's a member of the `api`
application." More-complex queries may do things like specifying constraints
based on latency:

```javascript
{
  "application": "api",
  "ops": [
    {
      "path": "/latency/http",
      "op": "$lte",
      "to": {"value": 100},
    }
  ],
}
```

That is, "route this message to any client that's a member of the `api`
application, where the value at that application's `/latency/http` key is less
than or equal to `100`."

As metadata is arbitrary JSON -- the only restriction being that the top-level
JSON is an object -- you can query effectively-infinitely-nested structures.
You can query paths with a syntax inspired by
[JSON Patch](http://jsonpatch.com/).

For more about how the query language works, see
[the relevant docs](https://github.com/queer/singyeong/blob/master/PROTOCOL.md#%EC%8B%A0%EA%B2%BD-node-queries)

#### Delivery guarantees

Messages are delivered at-least-zero times. That is, speaking broadly, your
messages will be delivered exactly once, but there are cases (network issues
etc.) that can lead to either no delivery, or more than one delivery, of the
same message.

## What about test coverage and the like?

You can run tests with `mix test`. Note that the plugin tests **WILL FAIL**
unless you set up the [test plugin](https://github.com/queer/singyeong-test-plugin)
in `priv/test/plugin/`. If you don't want to deal with the plugin-related code
when running tests (tho you REALLY should care...), you can skip those tests by
running `mix test --exclude plugin`.

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

신경 means nerve, and since the nervous system is how the entire body
communicates, it seemed like a fitting name for a messaging system. I
considered naming this something like 등뼈 (deungppyeo, "spine"/"backbone") or
회로망 (hoelomang, "network") or even 별자리 (byeoljali, "constellation), but I
figured that 신경 would be easier for people who don't know Korean to
pronounce, as well as being easier to find from GitHub search.
