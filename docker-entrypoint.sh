#!/bin/bash
epmd -daemon && MIX_ENV=prod mix phx.server