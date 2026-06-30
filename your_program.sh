#!/bin/sh

set -e

(
  cd "$(dirname "$0")"

  cd gleam
  gleam build

  cd ..
  mix escript.build
  mv codecrafters_bittorrent /tmp/codecrafters-build-bittorrent-elixir
)

exec /tmp/codecrafters-build-bittorrent-elixir "$@"
