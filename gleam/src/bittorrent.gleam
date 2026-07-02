import argv
import bencode
import gleam/bit_array
import gleam/crypto
import gleam/io
import gleam/json
import gleam/result.{map_error, try}
import gleam/string
import peer_protocol
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

    ["download_piece", ..rest] ->
      case rest {
        ["-o", filename, torrent_file, piece_index] -> {
          todo
        }
        _ -> Error(InsufficientArguments("download_piece"))
      }

    [command, ..] -> Error(UnknownCommand(command))
  }
}

pub type CmdError {
  UnknownCommand(String)
  InvalidArguments
  InsufficientArguments(String)
  AppStartError(StartError)
  FileError(simplifile.FileError)
  DecodeError(bencode.DecodeError)
  TorrentError(torrent.TorrentError)
  TrackerError(tracker.TrackerError)
  PeerError(peer_protocol.PeerError)
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

  use bits <- try(simplifile.read_bits(filename) |> map_error(FileError))
  use data <- try(bencode.decode(bits) |> map_error(DecodeError))

  use peer_peer_id <- try(
    peer_protocol.handshake(endpoint, data, peer_id)
    |> map_error(PeerError),
  )

  io.println(
    "Peer ID: "
    <> peer_peer_id
    |> bit_array.base16_encode
    |> string.lowercase,
  )
  Ok(Nil)
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
    InsufficientArguments(command) ->
      "Insufficient arguments for `" <> command <> "`"
    AppStartError(StartError(reason)) -> reason
    FileError(err) -> simplifile.describe_error(err)
    DecodeError(err) -> bencode.describe_error(err)
    TorrentError(err) -> torrent.describe_error(err)
    TrackerError(err) -> tracker.describe_error(err)
    PeerError(err) -> peer_protocol.describe_error(err)
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
