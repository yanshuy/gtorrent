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
import gleam/uri
import simplifile
import torrent/download
import torrent/peer/protocol
import torrent/peer/session
import torrent/torrent
import tracker

pub fn main() {
  execute(argv.load().arguments)
}

pub fn execute(args: List(String)) {
  start([Inets, Crypto, Asn1, PublicKey, Ssl])
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

    ["download", ..rest] ->
      case rest {
        ["-o", download_path, torrent_file] ->
          cmd_download(download_path, torrent_file)
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
  InvalidEndpoint

  FileError(simplifile.FileError)
  DecodeError(bencode.BencodeError)
  TrackerError(tracker.TrackerError)
  ProtocolError(protocol.ProtocolError)
  PeerError(session.PeerError)
  TorrentError(download.TorrentError)
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

fn info(filename: String) -> Result(torrent.TorrentInfo, CmdError) {
  use bits <- try(simplifile.read_bits(filename) |> map_error(FileError))
  use data <- try(bencode.decode(bits) |> map_error(DecodeError))

  torrent.parse(data) |> map_error(DecodeError)
}

fn cmd_info(filename: String) -> Result(Nil, CmdError) {
  use torrent <- try(info(filename))

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
  use peer_id <- try(load_peer_id() |> map_error(FileError))

  use torrent <- try(info(filename))
  use peers <- try(
    tracker.get_peers(torrent, peer_id) |> map_error(TrackerError),
  )
  io.println(string.join(peers, with: "\n"))
  Ok(Nil)
}

fn new_endpoint(endpoint: String) -> Result(protocol.Endpoint, Nil) {
  case string.split(endpoint, on: ":") {
    [ipv4, port_str] -> {
      use port <- try(int.parse(port_str))
      Ok(protocol.Endpoint(ipv4, port))
    }
    _ -> Error(Nil)
  }
}

fn cmd_handshake(filename: String, endpoint: String) -> Result(Nil, CmdError) {
  use peer_id <- try(load_peer_id() |> map_error(FileError))
  use torrent <- try(info(filename))

  use endpoint <- try(new_endpoint(endpoint) |> replace_error(InvalidEndpoint))
  use #(_socket, peer_peer_id) <- try(
    protocol.handshake(endpoint, torrent.info_hash, peer_id)
    |> map_error(ProtocolError),
  )
  let protocol.PeerId(id) = peer_peer_id
  io.println(
    "Peer ID: "
    <> id
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
  use peer_id <- try(load_peer_id() |> map_error(FileError))
  use torrent <- try(info(torrent_file))

  use peers <- try(
    tracker.get_peers(torrent, peer_id)
    |> map_error(TrackerError),
  )

  use endpoint <- try(
    peers
    |> list.first
    |> replace_error(InvalidArguments),
  )

  use endpoint <- try(
    new_endpoint(endpoint)
    |> replace_error(InvalidEndpoint),
  )

  use piece <- try(
    torrent.new_pieces(torrent.length, torrent.piece_length, torrent.pieces)
    |> list.drop(piece_index)
    |> list.first
    |> replace_error(InvalidPieceIndex(piece_index)),
  )
  download.download_piece(download_path, endpoint, torrent, peer_id, piece)
  |> map_error(TorrentError)
}

fn cmd_download(
  download_path: String,
  torrent_file: String,
) -> Result(Nil, CmdError) {
  use peer_id <- try(load_peer_id() |> map_error(FileError))
  use torrent <- try(info(torrent_file))

  use peer_endpoints <- try(
    tracker.get_peers(torrent, peer_id) |> map_error(TrackerError),
  )
  use endpoints <- try(
    peer_endpoints
    |> list.try_map(fn(endpoint) {
      new_endpoint(endpoint) |> replace_error(InvalidEndpoint)
    }),
  )
  let state =
    download.download_torrent(download_path, endpoints, torrent, peer_id)
    |> map_error(TorrentError)
  echo state
  io.println("download complete") |> Ok
}

fn load_peer_id() -> Result(protocol.PeerId, simplifile.FileError) {
  case simplifile.read_bits(".peer_id") {
    Ok(peer_id) -> Ok(protocol.PeerId(peer_id))

    _ -> {
      let peer_id = crypto.strong_random_bytes(20)
      use _ <- try(simplifile.write_bits(".peer_id", peer_id))
      Ok(protocol.PeerId(peer_id))
    }
  }
}

fn describe_cmd_error(error: CmdError) {
  case error {
    UnknownCommand(command) -> "Unknown command: " <> command
    InvalidArguments -> "Usage: your_program.sh <command> <args>"
    InsufficientArguments(command) ->
      "Insufficient arguments for `" <> command <> "`"
    InvalidEndpoint -> "Invalid endpoint. Expected <ip>:<port>."
    InvalidPieceIndex(index) -> "Invalid piece index: " <> int.to_string(index)
    FileError(err) -> simplifile.describe_error(err)
    DecodeError(err) -> bencode.describe_error(err)
    TrackerError(err) -> tracker.describe_error(err)
    PeerError(err) -> session.describe_error(err)
    ProtocolError(err) -> protocol.describe_error(err)
    TorrentError(err) -> download.describe_error(err)
  }
}

@external(erlang, "init", "stop")
pub fn stop(code: Int) -> Nil

@external(erlang, "bittorrent_ffi", "start")
fn application_start(app: Application) -> Result(Nil, StartError)

pub type Application {
  Inets
  Crypto
  Asn1
  PublicKey
  Ssl
}

pub type StartError {
  StartError(reason: String)
}

fn start(apps: List(Application)) {
  list.each(apps, fn(app) {
    case application_start(app) {
      Error(err) -> {
        io.println_error(err.reason)
        stop(1)
      }
      Ok(_) -> Nil
    }
  })
}
