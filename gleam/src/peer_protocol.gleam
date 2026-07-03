import bencode
import gleam/bit_array
import gleam/bool
import gleam/crypto
import gleam/int
import gleam/list
import gleam/result.{map_error, replace_error, try}
import gleam/string
import mug.{ConnectionOptions}

pub type ProtocolError {
  InvalidEndpoint
  InvalidResponse
  InfoHashMismatch
  TCPError(mug.Error)
  UnknownMessageId(Int)
  UnexpectedMessage(Int)
  ProtocolError(String)
}

pub type PeerMessage {
  Choke
  Unchoke
  Interested
  NotInterested
  Have
  BitField(BitArray)
  Request(piece_index: Int, begin: Int, length: Int)
  Piece(piece_index: Int, begin: Int, block: BitArray)
}

pub type PeerState {
  PeerState(choked: Bool, interested: Bool)
}

pub type PieceDownload {
  PieceDownload(
    index: Int,
    length: Int,
    hash: BitArray,
    offset: Int,
    blocks: List(BitArray),
  )
}

pub type PeerOutcome {
  PieceDownloaded(BitArray)
  PeerDoesNotHavePiece
}

const block_size = 16_384

const message_timeout = 5000

pub fn one_piece(
  torrent: bencode.Torrent,
  endpoint: String,
  piece_index: Int,
  hash piece_hash: BitArray,
  peer_id peer_id: BitArray,
) -> Result(BitArray, ProtocolError) {
  use #(ip4_addr, port) <- try(
    validate_endpoint(endpoint) |> replace_error(InvalidEndpoint),
  )
  use socket <- try(connect(ip4_addr, port))
  use _peer_peer_id <- try(peer_handshake(socket, torrent.info_hash, peer_id))
  use outcome <- try(peer_exchange(
    socket,
    PeerState(choked: True, interested: False),
    PieceDownload(
      index: piece_index,
      length: piece_length(piece_index, torrent.length, torrent.piece_length),
      hash: piece_hash,
      offset: 0,
      blocks: [],
    ),
  ))

  case outcome {
    PieceDownloaded(piece) -> Ok(piece)
    PeerDoesNotHavePiece -> Error(ProtocolError("They dont have it"))
  }
}

fn connect(host: String, port: Int) -> Result(mug.Socket, ProtocolError) {
  mug.connect(ConnectionOptions(
    host: host,
    port: port,
    timeout: message_timeout,
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
) -> Result(BitArray, ProtocolError) {
  let handshake_msg_length = 20 + 8 + 20 + 20
  let handshake_msg = <<
    19:int,
    "BitTorrent protocol",
    0:size(8)-unit(8),
    info_hash:bits,
    peer_id:bits,
  >>
  use _ <- try(mug.send(socket, handshake_msg) |> map_error(TCPError))
  use handshake_back <- try(
    mug.receive_exact(socket, handshake_msg_length, message_timeout)
    |> map_error(TCPError),
  )
  case handshake_back {
    <<
      19:int,
      "BitTorrent protocol",
      _:size(8)-unit(8),
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

fn peer_exchange(
  socket: mug.Socket,
  state: PeerState,
  piece: PieceDownload,
) -> Result(PeerOutcome, ProtocolError) {
  use message <- try(receive_message(socket))
  case message {
    Choke -> continue(socket, PeerState(..state, choked: True), piece)
    Unchoke -> continue(socket, PeerState(..state, choked: False), piece)

    Have -> peer_exchange(socket, state, piece)
    BitField(payload) -> {
      use state <- try(handle_bit_field(socket, payload, state))
      continue(socket, state, piece)
    }
    Piece(_, _, _) -> {
      use piece <- try(handle_piece_block(message, piece))

      case piece.offset == piece.length {
        False -> {
          use _ <- try(request_piece(socket, piece))
          peer_exchange(socket, state, piece)
        }
        True -> {
          let binary = list.reverse(piece.blocks) |> bit_array.concat
          use _ <- try(verify_piece(binary, piece.hash))
          Ok(PieceDownloaded(binary))
        }
      }
    }
    message -> Error(UnexpectedMessage(peer_message_id(message)))
  }
}

fn continue(
  socket: mug.Socket,
  state: PeerState,
  piece: PieceDownload,
) -> Result(PeerOutcome, ProtocolError) {
  case state {
    PeerState(choked: _, interested: False) -> Ok(PeerDoesNotHavePiece)
    PeerState(choked: False, interested: True) -> {
      use _ <- try(request_piece(socket, piece))
      peer_exchange(socket, state, piece)
    }
    PeerState(choked: True, interested: True) ->
      peer_exchange(socket, state, piece)
  }
}

fn handle_bit_field(
  socket: mug.Socket,
  payload: BitArray,
  state: PeerState,
) -> Result(PeerState, ProtocolError) {
  let interested = True

  case interested {
    True -> {
      let id = peer_message_id(Interested)
      let message = <<1:big-size(4)-unit(8), id:int>>
      use _ <- try(mug.send(socket, message) |> map_error(TCPError))
      Ok(PeerState(..state, interested: True))
    }
    False -> {
      let id = peer_message_id(NotInterested)
      let message = <<1:big-size(4)-unit(8), id:int>>
      use _ <- try(mug.send(socket, message) |> map_error(TCPError))
      Ok(PeerState(..state, interested: False))
    }
  }
}

fn handle_piece_block(
  message: PeerMessage,
  piece: PieceDownload,
) -> Result(PieceDownload, ProtocolError) {
  let assert Piece(peer_piece_index, begin, block) = message

  use <- bool.guard(
    peer_piece_index != piece.index,
    return: Error(ProtocolError("piece index mismatch")),
  )
  use <- bool.guard(
    begin != piece.offset,
    return: Error(ProtocolError("piece index mismatch")),
  )
  let rem = piece.length - begin
  let expected_length = case rem > block_size {
    True -> block_size
    False -> rem
  }
  let rx_block_size = bit_array.byte_size(block)
  use <- bool.guard(
    rx_block_size != expected_length,
    return: Error(ProtocolError("incomplete block")),
  )

  Ok(
    PieceDownload(..piece, offset: piece.offset + rx_block_size, blocks: [
      block,
      ..piece.blocks
    ]),
  )
}

fn request_piece(
  socket: mug.Socket,
  piece: PieceDownload,
) -> Result(Nil, ProtocolError) {
  let PieceDownload(index, length, _hash, offset, _blocks) = piece

  let block_length = int.min(length - offset, block_size)
  let req = Request(piece_index: index, begin: offset, length: block_length)
  let id = peer_message_id(req)

  let request_message = <<
    13:big-size(4)-unit(8),
    id:int,
    req.piece_index:big-size(4)-unit(8),
    req.begin:big-size(4)-unit(8),
    req.length:big-size(4)-unit(8),
  >>
  mug.send(socket, request_message) |> map_error(TCPError)
}

fn receive_message(socket: mug.Socket) -> Result(PeerMessage, ProtocolError) {
  use bits <- try(
    mug.receive_exact(socket, 4, message_timeout) |> map_error(TCPError),
  )
  let assert <<message_length:unsigned-big-size(4 * 8)>> = bits

  case message_length {
    // keep alive
    0 -> receive_message(socket)
    _ -> {
      use message <- try(
        mug.receive_exact(socket, message_length, message_timeout)
        |> map_error(TCPError),
      )
      parse_message(message)
    }
  }
}

fn parse_message(message: BitArray) -> Result(PeerMessage, ProtocolError) {
  let assert <<message_id, payload:bits>> = message
  case message_id {
    0 -> Ok(Choke)
    1 -> Ok(Unchoke)
    2 -> Ok(Interested)
    3 -> Ok(NotInterested)
    4 -> Ok(Have)
    5 -> Ok(BitField(payload))
    6 -> {
      let assert <<
        piece_index:big-size(4)-unit(8),
        begin:big-size(4)-unit(8),
        length:big-size(4)-unit(8),
      >> = payload
      Ok(Request(piece_index, begin, length))
    }
    7 -> {
      let assert <<
        piece_index:big-size(4)-unit(8),
        begin:big-size(4)-unit(8),
        block:bits,
      >> = payload
      Ok(Piece(piece_index, begin, block))
    }
    id -> Error(UnknownMessageId(id))
  }
}

fn peer_message_id(message: PeerMessage) -> Int {
  case message {
    Choke -> 0
    Unchoke -> 1
    Interested -> 2
    NotInterested -> 3
    Have -> 4
    BitField(_) -> 5
    Request(_, _, _) -> 6
    Piece(_, _, _) -> 7
  }
}

fn verify_piece(binary: BitArray, hash: BitArray) {
  let calc = crypto.hash(crypto.Sha1, binary)

  case calc == hash {
    True -> Ok(Nil)
    False -> Error(ProtocolError("hashes dont match"))
  }
}

fn piece_length(index: Int, file_length: Int, piece_length: Int) -> Int {
  let piece_count = { file_length + piece_length - 1 } / piece_length
  case piece_count - 1 == index {
    True ->
      case file_length % piece_length {
        0 -> piece_length
        rem -> rem
      }
    False -> piece_length
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
  torrent: bencode.Torrent,
  peer_id: BitArray,
) -> Result(BitArray, ProtocolError) {
  use #(ip4_addr, port) <- try(
    validate_endpoint(endpoint) |> replace_error(InvalidEndpoint),
  )
  use socket <- try(connect(ip4_addr, port))
  peer_handshake(socket, torrent.info_hash, peer_id)
}

pub fn describe_error(error: ProtocolError) -> String {
  case error {
    InvalidEndpoint -> "Invalid endpoint. Expected <ip>:<port>."
    InvalidResponse -> "Received an invalid response from the peer"
    InfoHashMismatch -> "Peer responded with a different info hash"
    TCPError(err) -> mug.describe_error(err)
    ProtocolError(err) -> err
    UnknownMessageId(msg_id) -> "Unknown Message Id " <> int.to_string(msg_id)
    UnexpectedMessage(msg_id) ->
      "Unexpected peer message: " <> int.to_string(msg_id)
  }
}
