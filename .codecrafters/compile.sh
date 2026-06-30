#!/bin/sh
# This script is used to compile your program on CodeCrafters

set -e # Exit on failure
erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell
mix escript.build
mv codecrafters_bittorrent /tmp/codecrafters-build-bittorrent-elixir
