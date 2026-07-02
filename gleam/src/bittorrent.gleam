import argv
import bencode
import gleam/bit_array
import gleam/crypto
import gleam/int
import gleam/io
import gleam/json
import gleam/result.{map_error, replace_error, try}
import gleam/string
import handshake
import simplifile
import torrent
import tracker

pub fn main() {
  execute(argv.load().arguments)
}

pub fn execute(args: List(String)) {
  case execute_cmd(args) {
    Ok(_) -> Nil
    Error(err) -> {
      io.println_error(describe_cmd_error(err))
      stop(1)
    }
  }
}

pub fn execute_cmd(args: List(String)) -> Result(Nil, CmdError) {
  case args {
    [] -> Error(InvalidArguments)

    ["decode", ..rest] ->
      case rest {
        [encoded, ..] -> cmd_decode(encoded)
        [] -> Error(InsufficientArguments("decode"))
      }

    ["info", ..rest] ->
      case rest {
        [filename, ..] -> cmd_info(filename)
        [] -> Error(InsufficientArguments("info"))
      }

    ["peers", ..rest] ->
      case rest {
        [filename, ..] -> cmd_peers(filename)
        [] -> Error(InsufficientArguments("peers"))
      }

    ["handshake", ..rest] ->
      case rest {
        [filename, endpoint] -> cmd_handshake(filename, endpoint)
        _ -> Error(InsufficientArguments("handshake"))
      }

    [command, ..] -> Error(UnknownCommand(command))
  }
}

pub type CmdError {
  UnknownCommand(String)
  InvalidArguments
  InvalidEndpoint
  InsufficientArguments(String)
  AppStartError(StartError)
  FileError(simplifile.FileError)
  DecodeError(bencode.DecodeError)
  TorrentError(torrent.TorrentError)
  TrackerError(tracker.TrackerError)
  HandshakeError(handshake.HandshakeError)
}

fn cmd_decode(encode_str: String) -> Result(Nil, CmdError) {
  use value <- try(
    bit_array.from_string(encode_str)
    |> bencode.decode
    |> map_error(DecodeError),
  )
  let json_str = bencode.to_json(value) |> json.to_string
  io.println(json_str)
  Ok(Nil)
}

fn cmd_info(filename: String) -> Result(Nil, CmdError) {
  use bits <- try(simplifile.read_bits(filename) |> map_error(FileError))
  use data <- try(bencode.decode(bits) |> map_error(DecodeError))

  use _ <- try(torrent.print_info(data) |> map_error(TorrentError))
  Ok(Nil)
}

fn cmd_peers(filename: String) -> Result(Nil, CmdError) {
  use _ <- try(application_start(Inets) |> map_error(AppStartError))

  use peer_id <- try(load_peer_id() |> map_error(FileError))

  use bits <- try(simplifile.read_bits(filename) |> map_error(FileError))
  use data <- try(bencode.decode(bits) |> map_error(DecodeError))

  use peers <- try(tracker.get_peers(data, peer_id) |> map_error(TrackerError))

  io.println(string.join(peers, with: "\n"))
  Ok(Nil)
}

fn cmd_handshake(filename: String, endpoint: String) -> Result(Nil, CmdError) {
  use _ <- try(application_start(Inets) |> map_error(AppStartError))

  use peer_id <- try(load_peer_id() |> map_error(FileError))

  use #(ip_addr, port_str) <- try(
    validate_endpoint(endpoint) |> replace_error(InvalidEndpoint),
  )
  use port <- try(int.parse(port_str) |> replace_error(InvalidEndpoint))

  use bits <- try(simplifile.read_bits(filename) |> map_error(FileError))
  use data <- try(bencode.decode(bits) |> map_error(DecodeError))

  use _ <- try(
    handshake.handshake(ip_addr, port, data, peer_id)
    |> map_error(HandshakeError),
  )

  Ok(Nil)
}

fn validate_endpoint(endpoint: String) -> Result(#(String, String), Nil) {
  case string.split(endpoint, on: ":") {
    [ipv4, port] -> Ok(#(ipv4, port))
    _ -> Error(Nil)
  }
}

fn load_peer_id() -> Result(BitArray, simplifile.FileError) {
  case simplifile.read_bits(".peer_id") {
    Ok(peer_id) -> Ok(peer_id)

    _ -> {
      let peer_id = crypto.strong_random_bytes(20)
      use _ <- try(simplifile.write_bits(".peer_id", peer_id))
      Ok(peer_id)
    }
  }
}

fn describe_cmd_error(error: CmdError) {
  case error {
    UnknownCommand(command) -> "Unknown command: " <> command
    InvalidArguments -> "Usage: your_program.sh <command> <args>"
    InvalidEndpoint -> "Invalid endpoint. Expected <ip>:<port>."
    InsufficientArguments(command) ->
      "Insufficient arguments for `" <> command <> "`"
    AppStartError(StartError(reason)) -> reason
    FileError(err) -> simplifile.describe_error(err)
    DecodeError(err) -> bencode.describe_error(err)
    TorrentError(err) -> torrent.describe_error(err)
    TrackerError(err) -> tracker.describe_error(err)
    HandshakeError(err) -> handshake.describe_error(err)
  }
}

@external(erlang, "init", "stop")
pub fn stop(code: Int) -> Nil

@external(erlang, "bittorrent_ffi", "start")
fn application_start(app: Application) -> Result(Nil, StartError)

pub type Application {
  Inets
}

pub type StartError {
  StartError(reason: String)
}
