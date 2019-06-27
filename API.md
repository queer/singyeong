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

## Service discovery

### `GET /discovery/tags`

Discover an application id by the tags its clients have registered. Tags to be
queried are passed to this method as a urlencoded JSON array as the querystring
parameter `q`.

Requires authorization.

#### Example

```
> GET /api/v1/discovery/tags?q=[%22test%22,%22webscale%22]
> Authorization: password

< {
<   "status": "ok",
<   "result": ["app-1" "app-2"]
< }
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
