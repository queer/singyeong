# 신경 REST API

Some API docs, because using something Proper:tm: and Correct:tm: like Swagger
turned out to be a nightmare I don't even wanna touch. /sob

Current API version: `1`

All routes are prefixed with `/api/:version`, ex. `/api/v1`

## API info

### `GET /api/version`

Returns the current API and 신경 versions.

Does not require authorization.

#### Example

```
> GET /api/version

< {
<   "api": "v1",
<   "singyeong":"0.0.1"
< }
```

## Metadata querying

### `POST /query`

Runs the provided query against the metadata store and returns matching
clients.

#### Example

```
> POST /api/v1/query
> Content-Type: application/json
> Authorization: password
> {
>   "application": "users-service",
>   "ops": [{"latency": {"$lte": "100"}}]
> }

< Content-Type: application/json
< [
<   {
<     "app_id": "app",
<     "client_id": "client",
<     "metadata": {"latency": 50},
<     "socket_ip": "127.0.0.1",
<     "queues": ["test"],
<   }
< ]
```

## Request proxying

### `POST /proxy`

Proxy a request to a remote service based on its metadata. Queries are
REQUIRED for routing.

Requires authorization.

#### Example

```
> POST /api/v1/proxy
> Content-Type: application/json
> Authorization: password
> {
>   "method": "GET",
>   "route": "/users/1"
>   "query": {
>     "application": "users-service",
>     "ops": [{"latency": {"$lte": "100"}}]
>   }
> }

< Content-Type: application/json
< {
<   "id": 1,
<   "username": "test"
< }
```

## Plugin routes

Plugins may register REST routes of their own. These routes will be appended to
`/api/v1/plugin`, ex. a plugin route of `/my-plugin/test` will end up being
`/api/v1/plugin/my-plugin/test`.

Plugin routes **require** authentication.