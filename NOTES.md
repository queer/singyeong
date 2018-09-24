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
2.  Send the gateway a packet like this:
    ```Javascript
    {
      "op": 1,
      "d": {
        "client_id": "e6a1d8b2-54ff-4e0c-a301-0ff862539c2c",
      }
    }
    ```
    Your `client_id` should be unique among all clients that you connect to 
    신경. If you don't know how to do this nicely, look into UUID or snowflake
    libraries for your language of choice. 
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
  "ts": 0
}
```

## 신경 websocket opcodes

| opcode | name          | mode | description |
|--------|---------------|------|-------------|
| 0      | hello         | recv | Sent on initial connection to the gateway |
| 1      | identify      | send | Tell the gateway who you are |
| 2      | ready         | recv | The gateway has accepted you, and will send you packets |
| 3      | invalid       | recv | The gateway doesn't like you for some reason, and wants you to go away (more info will be included in the `error` field of `d`) |
| 4      | dispatch      | both | The gateway is sending you an event, or you are sending the gateway an event |
| 5      | heartbeat     | send | Send a heartbeat to the gateway |
| 6      | heartbeat_ack | recv | Gateway acknowledging the last heartbeat you sent |

## 신경 websocket dispatch

Dispatch packets are the most complicated packets that your client can send or
recv., so it gets a special section documenting it. Specifically, a dispatch
packet will have a very specific `d` field structure, which any compliant 
clients must follow. 

Dispatch send structure
```Javascript
{
  "op": 4, // 4 is dispatch
  "ts": 0,
  "d": {
    "t": "EVENT_TYPE",
    "sender": "client's ID here. Used for req-res type messages",
    "nonce": "some unique nonce value. Used for req-res type messages",
    "target": "TODO",
    "payload": {
      // Your request payload goes here
    }
  }
}
```
Dispatch recv. structure
```Javascript
{
  "op": 4, // 4 is dispatch
  "ts": 0,
  "d": {
    "t": "EVENT_TYPE",
    "sender": "client's ID here. Used for req-res type messages",
    "nonce": "some unique nonce value. Used for req-res type messages",
    "payload": {
      // Your request payload goes here
    }
  }
}
```
The main different between send and recv. is the `target` field, but the
distinction is important enough that it deserves to be specifically shown like
this. To summarize, the important part (beyond setting correct opcode) is to 
construct the `d` field correctly. Overall, it's structured like this:
```Javascript
{
  // The type of the event. Always sent. Used for both controlling the client's
  // 신경 data as well as for clients receiving events from 신경. To make this
  // distinction clearer, 신경 events will be prefixed with 
  // TODO: Come up with a consistent prefix
  // This field is optional for custom packets
  // This field is required for 신경 packets
  "t": "EVENT_TYPE",
  // The ID of the client sending this packet. Used for request-response-style
  // queries. 
  // This field is required
  "sender": "client id",
  // A 신경 query to determine how to route this packet. Uses client metadata
  // to determine routing. 
  // More info on 신경 querying to come later
  // This field is required
  "target": "TODO",
  // A unique nonce value, used for request-response-style queries. This field
  // is optional, and will only be used on clients
  "nonce": "unique nonce",
  // The actual data of the request. 신경 will not introspect this field at
  // all. Used only by clients
  // This field is required
  "payload": {
    // Request payload goes here
  }
}
```