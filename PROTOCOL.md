# 신경 protocol

The basics of how the 신경 protocol works.

## Basic 신경 Lifecycle

0.  Parse the provided DSN. A 신경 DSN is a string matching this regex:
    `s?singyeong:\/\/.+(:.+)?@[\w-]+(:\d{1,5})?\/?(\?encoding=(json|etf|msgpack))?`.
    `singyeong://` is for a normal websocket connection, whereas
    `ssingyeong://` is for an SSL connection. You can pass the `encoding` query
    param with any valid encoding (see the table below), and the server will
    send you all payloads in that format. If you don't specify an encoding,
    JSON encoding will be assumed.
    Since a regex alone isn't too useful, here's some examples of valid DSNs:
    ```
    singyeong://test@localhost
    ssingyeong://test:pass-word@localhost
    singyeong://test@localhost:4567
    ssingyeong://test:pass~-word@localhost:4921/
    singyeong://test:pass@localhost:21312?encoding=json
    ssingyeong://test:pass@host:12321/?encoding=etf
    ```
    If a port is not specified, you can assume that the port is 80.
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

## 신경 websocket encodings

Encoding can be specified by adding an `encoding` query param, ex
`/gateway/websocket?encoding=msgpack`. If no encoding is specified, JSON
encoding is assumed.

| name    | description |
|---------|-------------|
| json    | The client sends and receives JSON. |
| etf     | The client sends and receives ETF. Only available for non-restricted clients. |
| msgpack | The client sends and receives MessagePack. |


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
| 0      | `hello`         | recv | Sent on initial connection to the server. |
| 1      | `identify`      | send | Tell the server who you are. |
| 2      | `ready`         | recv | The server has accepted you, and will send you packets |
| 3      | `invalid`       | recv | Sent to tell you that an application-level issue with your payload occurred. |
| 4      | `dispatch`      | both | The server is sending you an event, or you are sending the gateway an event. |
| 5      | `heartbeat`     | send | Send a heartbeat to the server. |
| 6      | `heartbeat_ack` | recv | Server acknowledging the last heartbeat you sent. |
| 7      | `goodbye`       | recv | Sent to tell you to reconnect. Used for eg. load balancing. |
| 8      | `error`         | recv | Sent to tell you that an unrecoverable error occurred. |

## 신경 events, the right way

Beyond the structure described a few sections above this, the structure of the
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

The payload you send to tell the gateway who you are.
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
  "application_id": "my-cool-application",
  // Optional value. If you specify a password in the env. vars, you must send
  // the same password here, otherwise you get placed into restricted mode.
  "auth": "your long complicated password here",
  // Optional value. If you specify an IP here, the server will use this as the
  // client's IP for HTTP request proxying. This can be useful for a case where
  // you may want to have proxied requests to the client sent somewhere else.
  // This field is only applicable to non-restricted clients.
  "ip": "1.2.3.4"
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

| name              | mode | description |
|-------------------|------|-------------|
| `UPDATE_METADATA` | send | Update metadata on the server. The inner payload should be a key-value mapping of metadata |
| `SEND`            | both | Send a payload to a single client that matches the routing query |
| `BROADCAST`       | both | Send a payload to all clients that match the routing query |
| `QUERY_NODES`     | send | Returns all nodes matching the given routing query. This is intended to help with debugging, and SHOULD NOT BE USED OTHERWISE |
| `QUEUE`           | both | Queues a new message into the specified queue when sent. Indicates a queued message being received when received. |
| `QUEUE_CONFIRM`   | recv | Sends an acknowledgement of message queuing to the client. |
| `QUEUE_REQUEST`   | send | Adds the client to the list of clients awaiting messages. |
| `QUEUE_ACK`       | send | ACKs the message in the payload, indicating that it's been handled and doesn't need to be re-queued. |

The inner payloads for these events are as follows:

#### `UPDATE_METADATA`

```Javascript
{
  "key": {
    "type": "string",
    "value": "value"
  },
  "key2": {
    "type": "integer",
    "value": 123
  }
  // ...
}
```

Available metadata types:
- string
- integer
- float
- [version](https://hexdocs.pm/elixir/Version.html)
- list

### `SEND` / `BROADCAST`

When sending:
```Javascript
{
  // Routing query for finding receiving nodes
  "target": "routing query goes here",
  // Optional nonce, used by clients for req-res queries
  "nonce": "unique nonce",
  "payload": {
    // Whatever data you want to pass goes here
  }
}
```

When receiving:
```Javascript
{
  // Optional nonce, used by clients for req-res queries
  "nonce": "unique nonce",
  "payload": {
    // Whatever data you want to pass goes here
  }
}
```

The main difference is the presence of the `target` field in the payload when
sending a dispatch event.

### `QUERY_NODES`

The inner payload is a node query as described below.

### `QUEUE`

The inner payload is more or less exactly the same as `SEND` / `BROADCAST`,
except with an additional `queue` key. When receiving a queued message, the
inner payload is a bit more complicated, mainly so that the server can indicate
the queue that the message came from, and the id of the message, so that your
client can ack properly.

When sending:
```Javascript
{
  "queue": "my-queue-name",
  "target": "routing query goes here",
  "nonce": "unique nonce",
  "payload": {
    // Whatever data you want to pass goes here
  }
}
```

When receiving:
```Javascript
{
  "nonce": "unique nonce",
  "payload": {
    "queue": "my-queue-name",
    "id": "id-for-acks",
    "payload": "your payload here"
  }
}
```

### `QUEUE_CONFIRM`

Sent by the server to indicate that the message has been queued.

Inner payload:
```Javascript
{
  "queue" => "my-queue-name"
}
```

### `QUEUE_REQUEST`

Marks this client as ready to receive events from the specified queue. THIS
OPERATION DOES NOT SEND BACK A PAYLOAD.

Inner payload:
```Javascript
{
  "queue": "my-queue-name"
}
```

### `QUEUE_ACK`

Sent by the client to indicate acknowledgement of a message, telling the server
that it can be removed from the specified queue.

Inner payload:
```Javascript
{
  "queue": "my-queue-name",
  "id": "id-to-ack"
}
```

## 신경 node queries

신경 implements a MongoDB-inspired query language.

### Metadata types

- `string`
- `integer`
- `float`
- `version`
- `list`

### Query operators

Comparison:
- `$eq`: metadata value `==` incoming value
- `$ne`: metadata value `!=` incoming value
- `$gt`: metadata value `>` incoming value
- `$gte`: metadata value `>=` incoming value
- `$lt`: metadata value `<` incoming value
- `$lte`: metadata value `<=` incoming value
- `$in` - metadata value `in` incoming list
- `$nin` - metadata value `not in` incoming list
- `$contains` - incoming value `in` metadata list
- `$ncontains` - incoming value `not in` metadata list

Logical:
- `$and`
- `$or`
- `$nor`

Element "operators" are not supported mainly because 신경 will enforce types
and value existence automatically, and return errors if your query is invalid.

Basically, you should be interpreting this section as "It works sorta kinda
like the MongoDB query language if you squint a little and look at it sideways,
but expect some weird things."

For more about MongoDB, see the following:

- https://docs.mongodb.com/manual/tutorial/query-documents/
- https://docs.mongodb.com/manual/reference/operator/query/

### Query selectors

Selectors allow you to select **one** matching client by means that would
otherwise be impossible with a query. For example, "select the client with the
lowest latency" would not be doable without selectors.

The following selectors exist:
- `$min`: Minimum value of `key`
- `$max`: Maximum value of `key`
- `$avg`: Average value of `key`

Currently, each selector can only operate on a single metadata key, and only
a single selector can be used. This is subject to change in the future.

### Query formatting

Queries are effectively just JSON objects. At some point there may be a "nice"
higher-level query language, but that can come later. A valid query is a JSON
object like the following:

```Javascript
{
  // ID of the application to query against
  "application": "application id here",
  // Whether or not to allow restricted-mode clients in the query results
  "restricted": true,
  // The key used for consistent-hashing when choosing a client from the output
  "key": "1234567890",
  // Whether or not this payload can be dropped if it isn't routable
  "droppable": true,
  // Whether or not this query is optional, ie. will be ignored and a client
  // will be chosen randomly if it matches nothing.
  "optional": true,
  // The ops used for querying. See the description(s) above
  "ops": [
    {
      "key": {
        "$eq": "value"
      }
    },
    {
      "key2": {
        "$lte": 1234
      }
    },
    {
      "key3": {
        "$and": [
          {"$gt": "10"},
          {"$lt": 20}
        ]
      }
    },
    {
      "key4": {
        "$in": [
          "123",
          "456"
        ]
      }
    }
  ],
  // The selector used. May be null. See the description(s) above.
  "selector": {"$min": "key"},
}
```

For a more-compact example:

```Javascript
{
  "application": "application id here",
  "key": "1234567890",
  "restricted": true,
  "droppable": true,
  "optional": true,
  "ops": [
    {"key": {"$eq": "value"}},
    {"key2": {"$lte": 1234}},
  ]
}
```

The `restricted` key sets whether or not the query can select a restricted-mode
client as the target of the query. The default is `false` and this will be
assumed if the value is not provided in the query. That is, if `restricted` is
`true`, **any client of the given application that is in restricted-mode may
receive the data being sent.** If you use 신경 as a websocket gateway, be sure
that you handle restrictions correctly!

The `key` key is the value used for consistent hashing. However, due to the
dynamic nature of 신경, the clients being hashed against cannot be guaranteed
to be the same. Because of this, 신경 "consistent hashes" are BEST-EFFORT. That
is, **a "consistently-hashed" message's target will always be the same client
if and only if the set of clients returned by the query does not change.**

The `droppable` key explicitly sets whether a specific message can be dropped
if it cannot be routed. Specifically, if a message's routing query returns no
results, and the value of `droppable` is `true`, the message will be silently
dropped.

The `optional` key marks the query as, well, optional -- if the query fails to
return any matching clients, it is ignored and the query is rerun as though
there were no ops / selectors specified.

### Why invent a new-ish query language?

I didn't want to tie the querying functionality to any specific datastore,
didn't want to invent something silly like a new SQL dialect, and also had the
constraint of clients that connect not necessarily having consistent metadata
layouts or similar, so anything more complicated than a key-value store becomes
rather difficult to work with in terms of actually storing and retrieving data.

## 신경 metadata store

신경 stores metadata in Mnesia. By storing metadata in 신경 you're able to
take advantage of target queries for message routing.

When connecting to the 신경 websocket gateway, the identify payload that your
client sends must include `application_id` and `client_id` fields; these fields
are a requirement as they're the main keys used for the majority of routing
queries.

### Important things to consider

**Client metadata is NOT persisted across server restarts!** Your client is
responsible for caching whatever metadata needs to be set so that it can be
restored on reconnect, as a client's metadata is always cleared when it
disconnects.

**Client metadata updates are applied lazily.** This is done to make sure that
a single client's connection PID cannot be crushed by a flood of updates all at
once. Currently, a single metadata queue worker will process 50 updates/second,
and anything beyond that is left in the queue to be processed later.
