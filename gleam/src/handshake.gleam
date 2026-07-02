import bencode
import gleam/bit_array
import gleam/io
import gleam/result.{map_error, try}
import gleam/string
import mug.{ConnectionOptions}
import torrent

pub type HandshakeError {
  InvalidHandshake
  InfoHashMismatch
  TorrentError(torrent.TorrentError)
  HandshakeError(String)
  TCPError(mug.Error)
}

pub fn handshake(
  host: String,
  port: Int,
  torrent: bencode.Bencode,
  peer_id: BitArray,
) -> Result(Nil, HandshakeError) {
  use dict <- try(torrent.dict(torrent) |> map_error(TorrentError))
  use info_entries <- try(
    torrent.get_entries(dict, "info") |> map_error(TorrentError),
  )
  let info_hash = torrent.digest_entries(info_entries)

  let handshake_msg = <<
    19:int,
    "BitTorrent protocol",
    0:size(8)-unit(8),
    info_hash:bits,
    peer_id:bits,
  >>

  use socket <- try(connect(host, port))

  use _ <- try(mug.send(socket, handshake_msg) |> map_error(TCPError))

  use handshake_back <- try(mug.receive(socket, 500) |> map_error(TCPError))
  use peer_peer_id <- try(validate_handshake_message(info_hash, handshake_back))

  io.println(
    "Peer ID: "
    <> peer_peer_id
    |> bit_array.base16_encode
    |> string.lowercase,
  )

  Ok(Nil)
}

fn connect(host: String, port: Int) -> Result(mug.Socket, HandshakeError) {
  mug.connect(ConnectionOptions(
    host: host,
    port: port,
    timeout: 1000,
    ip_version_preference: mug.Ipv4Only,
  ))
  |> map_error(fn(err) {
    case err {
      mug.ConnectFailedIpv4(err) -> TCPError(err)
      _ -> panic
    }
  })
}

fn validate_handshake_message(
  info_hash: BitArray,
  resp: BitArray,
) -> Result(BitArray, HandshakeError) {
  case resp {
    <<
      19:int,
      "BitTorrent protocol",
      0:size(8)-unit(8),
      rev_info_hash:bytes-size(20)-unit(8),
      peer_id:bytes-size(20)-unit(8),
    >> -> {
      case rev_info_hash == info_hash {
        True -> Ok(peer_id)
        False -> Error(InfoHashMismatch)
      }
    }
    _ -> Error(InvalidHandshake)
  }
}

pub fn describe_error(error: HandshakeError) -> String {
  case error {
    InvalidHandshake ->
      "Received malformed handshake (expected 68-byte BitTorrent handshake)"
    InfoHashMismatch -> "Peer responded with a different info hash"
    TCPError(err) -> mug.describe_error(err)
    TorrentError(err) -> torrent.describe_error(err)
    HandshakeError(msg) -> msg
  }
}
