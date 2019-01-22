Some API docs, because using something Proper:tm: and Correct:tm: like Swagger
turned out to be a nightmare I don't even wanna touch. /sob

Current API version: 1

All routes are prefixed with `/api/:version`

## Service discovery

### `GET /discovery/tags`

Discover an application id by the tags its clients have registered. Tags to be
queried are passed to this method as a urlencoded JSON array as the querystring
parameter `q`.

#### Example

```
> GET /discovery/tags?q=[%22test%22,%20%22webscale%22]

{
  "status": "ok",
  "result": ["app-1" "app-2"]
}
```