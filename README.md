# 신경

Singyeong (신경) is the nerve-center of your microservices-based application. 

I have it on good authority (read: Google Translate) that 신경 means "nerve." I
considered naming this something like 등뼈 (deungppyeo, "spine"/"backbone") or 
회로망 (hoelomang, "network") or even 별자리 (byeoljali, "constellation), but I 
figured that 신경 would be easier for people who don't know Korean to pronounce.

To be serious, 신경 is a Redis-backed message queue of sorts. Clients connect 
over a websocket (protocol defined in NOTES.md), and can send messages that can
be routed to clients based on the metadata that the clients store on the 
server.

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

## TODO

- restricted mode