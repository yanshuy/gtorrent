import bencode
import gleam/dict
import gleam/int
import gleam/result.{map_error, replace_error, try}
import gleam/string
import mug.{ConnectionOptions}
import torrent
import tracker

pub type PeerError {
  InvalidEndpoint
  InvalidResponse
  InfoHashMismatch
  TCPError(mug.Error)
  TorrentError(torrent.TorrentError)
  TrackerError(tracker.TrackerError)
  ProtocolError(String)
}

pub type ChokeState {
  Choked
  Unchoked
}

pub type InterestState {
  Interested
}

pub type PeerState {
  BitField
  PeerState(choke: ChokeState, interest: InterestState)
}

pub fn ask_one_piece(
  torrent: bencode.Bencode,
  peer_id: BitArray,
) -> Result(Nil, PeerError) {
  use dict <- try(torrent.dict(torrent) |> map_error(TorrentError))
  use tracker_url <- try(
    torrent.get_string(dict, "announce") |> map_error(TorrentError),
  )
  use info_entries <- try(
    torrent.get_entries(dict, "info") |> map_error(TorrentError),
  )
  let info_hash = torrent.digest_entries(info_entries)

  use peers <- try(
    tracker.get_peers(torrent, peer_id) |> map_error(TrackerError),
  )

  let assert [endpoint, ..] = peers
  use #(ip4_addr, port) <- try(
    validate_endpoint(endpoint) |> replace_error(InvalidEndpoint),
  )

  use socket <- try(connect(ip4_addr, port))
  use peer_peer_id <- try(peer_handshake(socket, info_hash, peer_id))

  use pieces <- try(
    torrent.get_string_bits(dict.from_list(info_entries), "pieces")
    |> map_error(TorrentError),
  )

  use _ <- try(peer_communicate(socket, BitField))
  todo
}

fn connect(host: String, port: Int) -> Result(mug.Socket, PeerError) {
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

pub fn peer_handshake(
  socket: mug.Socket,
  info_hash: BitArray,
  peer_id: BitArray,
) -> Result(BitArray, PeerError) {
  let handshake_msg = <<
    19:int,
    "BitTorrent protocol",
    0:size(8)-unit(8),
    info_hash:bits,
    peer_id:bits,
  >>
  use _ <- try(mug.send(socket, handshake_msg) |> map_error(TCPError))
  use handshake_back <- try(mug.receive(socket, 500) |> map_error(TCPError))

  case handshake_back {
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
    _ -> Error(InvalidResponse)
  }
}

fn peer_communicate(socket: mug.Socket, state: PeerState) {
  case state {
    BitField -> {
      use message <- try(mug.receive(socket, 500) |> map_error(TCPError))
      use #(message_id, _payload) <- try(parse_peer_message(message))

      case message_id {
        5 -> peer_communicate(socket, PeerState(Choked, Interested))
        _ -> todo
        //what to do here?
      }
    }
    PeerState(choke: Choked, interest: Interested) -> {
      let interested = <<1:size(4)-unit(8), 2:int>>
      use _ <- try(mug.send(socket, interested) |> map_error(TCPError))

      use message <- try(mug.receive(socket, 500) |> map_error(TCPError))
      use #(message_id, _) <- try(parse_peer_message(message))

      case message_id {
        1 -> peer_communicate(socket, PeerState(Unchoked, Interested))
        _ -> todo
        // what to do ?
      }
    }
    PeerState(choke: Unchoked, interest: Interested) -> {
      use message <- try(mug.receive(socket, 500) |> map_error(TCPError))
      use #(message_id, _) <- try(parse_peer_message(message))
      todo
    }
  }
}

fn parse_peer_message(
  message: BitArray,
) -> Result(#(Int, BitArray), PeerError) {
  case message {
    <<
      msg_len:size(4)-unit(8),
      msg_id:int,
      payload:bits-size(msg_len - 1)-unit(8),
      _:bits,
    >> -> {
      Ok(#(msg_id, payload))
    }
    _ -> Error(InvalidResponse)
  }
}

fn validate_endpoint(endpoint: String) -> Result(#(String, Int), Nil) {
  case string.split(endpoint, on: ":") {
    [ipv4, port_str] -> {
      use port <- try(int.parse(port_str))
      Ok(#(ipv4, port))
    }
    _ -> Error(Nil)
  }
}

pub fn handshake(
  endpoint: String,
  torrent: bencode.Bencode,
  peer_id: BitArray,
) -> Result(BitArray, PeerError) {
  use #(ip4_addr, port) <- try(
    validate_endpoint(endpoint) |> replace_error(InvalidEndpoint),
  )
  use dict <- try(torrent.dict(torrent) |> map_error(TorrentError))
  use info_entries <- try(
    torrent.get_entries(dict, "info") |> map_error(TorrentError),
  )
  let info_hash = torrent.digest_entries(info_entries)

  use socket <- try(connect(ip4_addr, port))

  peer_handshake(socket, info_hash, peer_id)
}

pub fn describe_error(error: PeerError) -> String {
  case error {
    InvalidEndpoint -> "Invalid endpoint. Expected <ip>:<port>."
    InvalidResponse -> "Received an invalid response from the peer"
    InfoHashMismatch -> "Peer responded with a different info hash"
    TCPError(err) -> mug.describe_error(err)
    TorrentError(err) -> torrent.describe_error(err)
    TrackerError(err) -> tracker.describe_error(err)
    ProtocolError(msg) -> msg
  }
}
