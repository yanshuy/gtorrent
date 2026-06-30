#!/bin/sh
# This script is used to compile your program on CodeCrafters

set -e # Exit on failure

mix escript.build
mv codecrafters_bittorrent /tmp/codecrafters-build-bittorrent-elixir
