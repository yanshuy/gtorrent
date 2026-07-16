#!/bin/sh
# This script is used to compile your program on CodeCrafters

set -e

erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell

cd "$(dirname "$0")/.."

GLEAM_VERSION="1.17.0"

mkdir -p /tmp/gleam-install
cd /tmp/gleam-install

curl -L \
  "https://github.com/gleam-lang/gleam/releases/download/v${GLEAM_VERSION}/gleam-v${GLEAM_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
  -o gleam.tar.gz

tar -xzf gleam.tar.gz

chmod +x gleam

export PATH="/tmp/gleam-install:$PATH"

gleam --version

cd /app/gleam

# Remove cached build artifacts
rm -rf build

gleam build

cd /app

mix escript.build

mv codecrafters_bittorrent /tmp/codecrafters-build-bittorrent-elixir
