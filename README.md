# 신경

Singyeong (신경) is the nerve-center of your microservices-based application. 

I have it on good authority (read: Google Translate) that 신경 means "nerve." I
considered naming this something like 등뼈 (deungppyeo, "spine"/"backbone") or 
회로망 (hoelomang, "network") or even 별자리 (byeoljali, "constellation), but I 
figured that 신경 would be easier for people who don't know Korean to pronounce.

To be serious, 신경 is a message bus of sorts. Clients connect over a websocket
(protocol defined in NOTES.md), and can send messages that can be routed to
clients based on the metadata that the clients store on the server.

A (somewhat-untested) reference client can be found here: 
https://github.com/singyeong/java-client

Clients are stored under an org because I don't want them cluttering up my 
repos page. 

## How do I write my own client for it? How does it work internally? etc.

Check out NOTES.md.

## How do I run the tests?

`mix test`. ~~Of course, there are no tests because I forgot to write
them. Oops.~~

I finally added tests. ~~Please clap~~ More will likely be added over time.

## Configuration

Configuration is done via environment variables.

```Bash
# The port to run the websocket gateway on
PORT=4567
# The password that clients must send in order to connect. Optional.
AUTH="2d1e29fbe6895b3693112ff8d5061b3b584c64c0cf5fd638b7c552a8bf0b1e461904aff753c9924d32a5309c064408f797b68c2f78f7eab853165d4f7f097545"
iex -S mix phx.server
```

## Authentication

Note that **there is no ratelimit on authentication attempts**. This means that
a malicious client can constantly open connections and attempt passwords until
it gets the correct one. It is **highly** recommended that you use a very long,
probably-very-complicated password in order to help protect against this sort
of attack.
