#!/bin/bash

env PORT=4000 MIX_ENV=test mix coveralls.json
bash <(curl -s https://codecov.io/bash)