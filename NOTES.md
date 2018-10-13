# 신경 Notes

Some notes to myself so I don't forget

## 신경 flow

1.  Open a websocket connection to `/gateway/websocket`. The server will 
    immediately reply with a packet like this:
    ```Javascript
    {
      "op": 0,
      "d": {
        "heartbeat_interval": 45000,
      },
    }
    ```
    Your client should start sending a heartbeat packet every 
    `heartbeat_interval` milliseconds (more on this later). 
2.  Send the gateway a packet like this to identify:
    ```Javascript
    {
      "op": 1,
      "d": {
        "client_id": "e6a1d8b2-54ff-4e0c-a301-0ff862539c2c",
        "application_id": "my-cool-application",
      }
    }
    ```
    Your `client_id` should be unique among all clients that you connect to 
    신경. If you don't know how to do this nicely, look into UUID or snowflake
    libraries for your language of choice. 
    
    Your `application_id` can - and should be - shared among many clients. This
    is because the `application_id` is what's used for actually doing by-app 
    routing queries within 신경. 
3.  The gateway will respond with a packet like this:
    ```Javascript
    {
      "op": 2,
      "d": {
        "client_id": "e6a1d8b2-54ff-4e0c-a301-0ff862539c2c",
      }
    }
    ```
    and you will be considered connected. Be sure to heartbeat so that the 
    gateway doesn't disconnect you!

## 신경 websocket packet structure

```Javascript
{
  // Opcode of this packet. Refer to the table below for more information
  "op": 0,
  // Data payload of this packet. Will always be a JSON object
  "d": {
    // Whatever data the packet needs to send you
  },
  // Timestamp of the packet when it was sent on the server. Can be used for 
  // ex. latency calculations
  "ts": 0,
  // Type of the event. This only sent for `dispatch` events
  "t": "EVENT_TYPE"
}
```

## 신경 websocket opcodes

| opcode | name            | mode | description |
|--------|-----------------|------|-------------|
| 0      | `hello`         | recv | Sent on initial connection to the gateway |
| 1      | `identify`      | send | Tell the gateway who you are |
| 2      | `ready`         | recv | The gateway has accepted you, and will send you packets |
| 3      | `invalid`       | recv | The gateway doesn't like you for some reason, and wants you to go away (more info will be included in the `error` field of `d`) |
| 4      | `dispatch`      | both | The gateway is sending you an event, or you are sending the gateway an event |
| 5      | `heartbeat`     | send | Send a heartbeat to the gateway |
| 6      | `heartbeat_ack` | recv | Gateway acknowledging the last heartbeat you sent |

## 신경 events, the right way

Beyond the structure described a feww sections above this, the structure of the
inner payload of 신경 events is quite important. The correct structure for 
these is described below:

### hello

The initial payload you receive after connecting to 신경.
```Javascript
{
  // Send a heartbeat every `heartbeat_interval` milliseconds. 
  // This value may change at any time, so don't hard-code it.
  "heartbeat_interval": 45000
}
```

### identify

The payload you send to tell the gateway who you are ~~before it disconnects 
you~~.
```Javascript
{
  // A unique client ID. If there is already a *healthy* client with this 
  // client id, your connection will be terminated with op 3.
  // If you don't know what to use for this, you should use something like a
  // UUID or snowflake.
  // This value may *not* contain spaces.
  "client_id": "19274eyuholdis3vhynurtlofkbhndvhvqkl34wjgyhnewri",
  // The name of the client application. This field is required, as it's the 
  // main thing used for routing queries. 
  // This value may *not* contain spaces.
  "application_name": "my-cool-application"
}
```

### ready

The payload that the gateway sends you after you correctly identify.
```Javascript
{
  "client_id": "The same client id you sent in :identify"
}
```

### dispatch

The payload you send the gateway OR the gateway sends you for sending events
for updating metadata, sending requests to other nodes, etc. This is somewhat
complicated, and gets its own section(s) below.

### heartbeat

The payload you send the gateway to keep your connection alive. 
```Javascript
{
  "client_id": "the same client id you sent in :identify"
}
```

### heartbeat_ack

The payload the gateway sends you when it receives your heartbeat.
```Javascript
{
  "client_id": "the same client id you sent in :identify"
}
```

## 신경 websocket dispatch

Dispatch packets are the most complicated packets that your client can send or
recv., so it gets a special section documenting it. Specifically, a dispatch
packet will have a very specific `d` field structure, which any compliant 
clients must follow. 

### 신경 dispatch events

| name              | description |
|-------------------|-------------|
| `UPDATE_METADATA` | Update metadata on the server. The inner payload should be a key-value mapping of metadata |
| `SEND`            | Send a payload to a single client that matches the routing query |
| `BROADCAST`       | Send a payload to all clients that match the routing query |

The inner payloads for these events are as follows:

#### `UPDATE_METADATA`

```Javascript
{
  "key": {
    "type": "string",
    "value": "value"
  }
  "key2": {
    "type": "integer",
    "value": 123
  }
  // ...
}
```

### `SEND` / `BROADCAST`

When sending:
```Javascript
{
  // Client ID sending the payload
  "sender": "your client id goes here",
  // Routing query for finding receiving nodes
  "target": "routing query goes here",
  // Optional nonce, used by clients for req-res queries
  "nonce": "unique nonce",
  "payload: {
    // Whatever data you want to pass goes here
  }
}
```

When receiving:
```Javascript
{
  // Client ID sending the payload
  "sender": "your client id goes here",
  // Optional nonce, used by clients for req-res queries
  "nonce": "unique nonce",
  "payload: {
    // Whatever data you want to pass goes here
  }
}
```

The main difference is the presence of the `target` field in the payload when
sending a dispatch event. 

## 신경 message queueing

When 신경 receives a dispatch packet from a client, it does not immediately 
query for a target and send the message. Rather, the dispatch is queued up to
be sent at a later time. This is mainly done so that ex. in the case of a 
mistake causing all clients to connect to a single 신경 node, it won't
(necessarily) overload the single node with trying to recv. *and* send all
dispatch packets at the same time, handle all dispatch queries, etc. 

신경 currently does message queueing with Redis, but this may change at some 
point in the future. 

## 신경 metadata store

신경 stores metadata in Redis. By storing metadata in 신경, you're able to 
take advantage of target queries for message routing. 

When connecting to the 신경 websocket gateway, the identify payload that your
client sends should include a `application_name` field; this field is a 
requirement as it's the main key used for the majority of routing queries. 