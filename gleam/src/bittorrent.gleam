import argv
import bencode
import gleam/bit_array
import gleam/crypto
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/result.{map_error, replace_error, try}
import gleam/string
import peer_protocol
import simplifile
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
        [torrent_file, ..] -> cmd_info(torrent_file)
        [] -> Error(InsufficientArguments("info"))
      }

    ["peers", ..rest] ->
      case rest {
        [torrent_file, ..] -> cmd_peers(torrent_file)
        [] -> Error(InsufficientArguments("peers"))
      }

    ["handshake", ..rest] ->
      case rest {
        [torrent_file, endpoint] -> cmd_handshake(torrent_file, endpoint)
        _ -> Error(InsufficientArguments("handshake"))
      }

    ["download_piece", ..rest] ->
      case rest {
        ["-o", download_path, torrent_file, piece_index] ->
          cmd_download_piece(download_path, torrent_file, piece_index)
        _ -> Error(InsufficientArguments("download_piece"))
      }

    [command, ..] -> Error(UnknownCommand(command))
  }
}

pub type CmdError {
  UnknownCommand(String)
  InvalidArguments
  InsufficientArguments(String)
  InvalidPieceIndex(Int)
  AppStartError(StartError)
  FileError(simplifile.FileError)
  DecodeError(bencode.DecodeError)
  TrackerError(tracker.TrackerError)
  PeerError(peer_protocol.ProtocolError)
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

  use torrent <- try(bencode.parse_torrent(data) |> map_error(DecodeError))

  io.println("Tracker URL: " <> torrent.announce)
  io.println("Length: " <> int.to_string(torrent.length))

  let encoded =
    torrent.info_hash
    |> bit_array.base16_encode
    |> string.lowercase
  io.println("Info Hash: " <> encoded)
  io.println("Piece Length: " <> int.to_string(torrent.piece_length))

  let hashes =
    torrent.pieces
    |> list.map(bit_array.base16_encode)
    |> list.map(string.lowercase)
    |> string.join(with: "\n")

  io.println("Piece Hashes: \n" <> hashes)
  Ok(Nil)
}

fn cmd_peers(filename: String) -> Result(Nil, CmdError) {
  use _ <- try(application_start(Inets) |> map_error(AppStartError))

  use peer_id <- try(load_peer_id() |> map_error(FileError))

  use bits <- try(simplifile.read_bits(filename) |> map_error(FileError))
  use data <- try(bencode.decode(bits) |> map_error(DecodeError))

  use torrent <- try(bencode.parse_torrent(data) |> map_error(DecodeError))
  use peers <- try(
    tracker.get_peers(torrent, peer_id) |> map_error(TrackerError),
  )

  io.println(string.join(peers, with: "\n"))
  Ok(Nil)
}

fn cmd_handshake(filename: String, endpoint: String) -> Result(Nil, CmdError) {
  use _ <- try(application_start(Inets) |> map_error(AppStartError))

  use peer_id <- try(load_peer_id() |> map_error(FileError))

  use bits <- try(simplifile.read_bits(filename) |> map_error(FileError))
  use data <- try(bencode.decode(bits) |> map_error(DecodeError))

  use torrent <- try(bencode.parse_torrent(data) |> map_error(DecodeError))
  use peer_peer_id <- try(
    peer_protocol.handshake(endpoint, torrent, peer_id)
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

fn cmd_download_piece(
  download_path: String,
  torrent_file: String,
  piece_index_str: String,
) -> Result(Nil, CmdError) {
  use piece_index <- try(
    int.parse(piece_index_str) |> replace_error(InvalidArguments),
  )
  use _ <- try(application_start(Inets) |> map_error(AppStartError))

  use peer_id <- try(load_peer_id() |> map_error(FileError))

  use bits <- try(simplifile.read_bits(torrent_file) |> map_error(FileError))
  use data <- try(bencode.decode(bits) |> map_error(DecodeError))

  use torrent <- try(bencode.parse_torrent(data) |> map_error(DecodeError))
  use peers <- try(
    tracker.get_peers(torrent, peer_id) |> map_error(TrackerError),
  )
  let assert [endpoint, ..] = peers

  use piece_hash <- try(
    torrent.pieces
    |> list.drop(piece_index)
    |> list.first
    |> replace_error(InvalidPieceIndex(piece_index)),
  )

  use piece <- try(
    peer_protocol.one_piece(
      torrent,
      endpoint,
      piece_index,
      hash: piece_hash,
      peer_id: peer_id,
    )
    |> map_error(PeerError),
  )

  simplifile.write_bits(download_path, piece) |> map_error(FileError)
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
    InvalidPieceIndex(index) -> "Invalid piece index: " <> int.to_string(index)
    AppStartError(StartError(reason)) -> reason
    FileError(err) -> simplifile.describe_error(err)
    DecodeError(err) -> bencode.describe_error(err)
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
