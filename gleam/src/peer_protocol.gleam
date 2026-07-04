import bencode
import gleam/bit_array
import gleam/bool
import gleam/crypto
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result.{map_error, replace_error, try}
import gleam/string
import mug.{ConnectionOptions}
import simplifile

pub type PeerMessage {
  Choke
  Unchoke
  Interested
  NotInterested
  Have
  BitField(BitArray)
  Request(piece_index: Int, begin: Int, length: Int)
  PieceMessage(piece_index: Int, begin: Int, block: BitArray)
}

pub type Piece {
  Piece(
    index: Int,
    hash: BitArray,
    length: Int,
    blocks: List(BitArray),
    remaining_requests: List(BlockRequest),
    outstanding_requests: dict.Dict(Int, BlockRequest),
  )
}

pub type BlockRequest {
  BlockRequest(begin: Int, length: Int)
}

pub type PeerSession {
  PeerSession(
    socket: mug.Socket,
    peer_id: PeerId,
    bit_field: Option(BitArray),
    piece: Option(Piece),
    choked: Bool,
    interested: Bool,
  )
}

pub type PeerOutcome {
  PieceDownloaded(BitArray)
  PeerDoesNotHavePiece
}

const block_size = 16_384

const message_timeout = 5000

pub fn new_session(socket: mug.Socket, peer_id: PeerId) -> PeerSession {
  PeerSession(
    socket,
    peer_id,
    bit_field: None,
    piece: None,
    choked: True,
    interested: False,
  )
}

fn new_piece(index: Int, hash: BitArray, length: Int) -> Piece {
  let requests = request_blocks(length)
  Piece(
    index: index,
    hash: hash,
    length: length,
    blocks: [],
    remaining_requests: requests,
    outstanding_requests: dict.new(),
  )
}

pub fn handshake(
  endpoint: String,
  info_hash: BitArray,
  peer_id: BitArray,
) -> Result(PeerSession, ProtocolError) {
  use #(ip4_addr, port) <- try(
    validate_endpoint(endpoint) |> replace_error(InvalidEndpoint),
  )
  use socket <- try(connect(ip4_addr, port))
  peer_handshake(socket, info_hash, peer_id)
}

pub fn connect(host: String, port: Int) -> Result(mug.Socket, ProtocolError) {
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
) -> Result(PeerSession, ProtocolError) {
  let handshake_msg = <<
    19:int,
    "BitTorrent protocol",
    0:size(8)-unit(8),
    info_hash:bits,
    peer_id:bits,
  >>
  use _ <- try(mug.send(socket, handshake_msg) |> map_error(TCPError))

  use handshake_back <- try(
    mug.receive_exact(socket, 20 + 8 + 20 + 20, message_timeout)
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
        True -> Ok(new_session(socket, PeerId(peer_id)))
        False -> Error(InfoHashMismatch)
      }
    }
    _ -> Error(InvalidResponse)
  }
}

pub type Torrent {
  Torrent(
    info: bencode.Torrent,
    download_path: String,
    piece_hash: dict.Dict(Int, BitArray),
    peers: List(PeerId),
  )
}

pub type PeerId {
  PeerId(BitArray)
}

fn new_torrent(
  torrent: bencode.Torrent,
  download_path: String,
  peers: List(PeerId),
) {
  let piece_hash =
    torrent.pieces
    |> list.index_map(fn(piece, index) { #(index, piece) })
    |> dict.from_list
  Torrent(
    info: torrent,
    download_path: download_path,
    piece_hash: piece_hash,
    peers: peers,
  )
}

pub fn fetch_torrent(
  torrent: bencode.Torrent,
  download_path: String,
  endpoints: List(String),
  peer_id: BitArray,
) -> Result(Nil, ProtocolError) {
  //connect to all endpoints
  let sessions =
    list.filter_map(endpoints, fn(endpoint) {
      handshake(endpoint, torrent.info_hash, peer_id)
    })
  //check what they have
  let bitfields =
    list.filter_map(sessions, fn(session) { receive_bitfield(session) })

  let peers = sessions |> list.map(fn(session) { session.peer_id })
  let torrent = new_torrent(torrent, download_path, peers)

  //assign piece
  let sessions = assign_pieces(torrent, sessions)
  todo
  // one_piece(session.socket, torrent, session.state, torrent.pieces, 0)
  // |> result.replace(Nil)
}

fn work(torrent, sessions) {
  list.each(sessions, fn(session) { peer_exchange(session) })
}

fn assign_pieces(
  torrent: Torrent,
  sessions: List(PeerSession),
) -> List(PeerSession) {
  let pieces = dict.to_list(torrent.piece_hash)
  keep_assigning(torrent, sessions, pieces, [])
}

fn keep_assigning(
  torrent: Torrent,
  sessions: List(PeerSession),
  pieces: List(#(Int, BitArray)),
  new_sessions: List(PeerSession),
) -> List(PeerSession) {
  case sessions, pieces {
    [], _ -> sessions
    _, [] -> new_sessions |> list.append(sessions)
    [session, ..sessions], [piece, ..pieces] -> {
      let #(index, hash) = piece
      let piece_length =
        piece_length(index, torrent.info.length, torrent.info.piece_length)
      let piece = new_piece(index, hash, piece_length)
      let new_ses = PeerSession(..session, piece: Some(piece))
      keep_assigning(torrent, sessions, pieces, [new_ses, ..new_sessions])
    }
  }
}

// pub fn one_piece(
//   socket: mug.Socket,
//   torrent: bencode.Torrent,
//   state: PeerState,
//   pieces: List(BitArray),
//   piece_index: Int,
// ) -> Result(Nil, ProtocolError) {
//   case pieces {
//     [piece_hash, ..rest] -> {
//       let length =
//         piece_length(piece_index, torrent.length, torrent.piece_length)
//       let piece_downlaod = new_piece(piece_index, length, piece_hash)

//       use #(new_state, outcome) <- try(peer_exchange(
//         socket,
//         state,
//         piece_downlaod,
//       ))
//       case outcome {
//         PieceDownloaded(piece) -> {
//           use _ <- try(
//             simplifile.append_bits(new_state.download_path, piece)
//             |> map_error(FileError),
//           )
//           one_piece(socket, torrent, new_state, rest, piece_index + 1)
//         }
//         PeerDoesNotHavePiece ->
//           one_piece(socket, torrent, new_state, rest, piece_index + 1)
//       }
//     }
//     [] -> Ok(Nil)
//   }
// }

fn receive_bitfield(
  session: PeerSession,
) -> Result(PeerSession, ProtocolError) {
  use message <- try(receive_message(session.socket))
  case message {
    BitField(bits) -> Ok(PeerSession(..session, bit_field: Some(bits)))
    _ -> receive_bitfield(session)
  }
}

fn peer_exchange(
  session: PeerSession,
) -> Result(#(BitArray, PeerSession), ProtocolError) {
  case session {
    PeerSession(bit_field: None, ..) -> {
      use session <- try(receive_bitfield(session))
      Ok(#(<<>>, session))
    }
    PeerSession(choked: _, interested: False, ..) -> continue(session)
    PeerSession(choked: False, interested: True, ..) -> {
      use _ <- try(request_piece(session))
      continue(session)
    }
    PeerSession(choked: True, interested: True, ..) -> continue(session)
  }
}

fn log(m: PeerMessage) {
  case m {
    PieceMessage(_, _, _) -> PieceMessage(..m, block: <<>>)
    _ -> m
  }
}

fn continue(
  session: PeerSession,
) -> Result(#(BitArray, PeerSession), ProtocolError) {
  use message <- try(receive_message(session.socket))
  echo log(message)
  case message {
    Choke -> peer_exchange(PeerSession(..session, choked: True))
    Unchoke -> peer_exchange(PeerSession(..session, choked: False))
    Have -> peer_exchange(session)
    BitField(_) ->
      Error(ProtocolError("Protocol violation got a 2nd bit field"))
    PieceMessage(_, _, _) -> {
      use piece <- try(handle_piece_block(session, message))
      case piece.remaining_requests {
        [_, ..] -> peer_exchange(session)
        [] -> {
          let binary = list.reverse(piece.blocks) |> bit_array.concat
          use _ <- try(verify_piece(binary, piece.hash))
          Ok(#(binary, session))
        }
      }
    }
    message -> Error(UnexpectedMessage(message_id(message)))
  }
}

fn handle_bit_field(
  session: PeerSession,
  bit_field: BitArray,
) -> Result(PeerSession, ProtocolError) {
  let interested = True

  case interested {
    True -> {
      let id = message_id(Interested)
      let message = <<1:big-size(4)-unit(8), id:int>>
      use _ <- try(mug.send(session.socket, message) |> map_error(TCPError))
      Ok(PeerSession(..session, interested: True))
    }
    False -> Ok(PeerSession(..session, interested: False))
  }
}

fn handle_piece_block(
  session: PeerSession,
  message: PeerMessage,
) -> Result(Piece, ProtocolError) {
  let assert Some(piece) = session.piece
  let assert PieceMessage(peer_piece_index, begin, block) = message
  use <- bool.guard(
    peer_piece_index != piece.index,
    return: Error(ProtocolError("piece index mismatch")),
  )
  let outstanding = dict.get(piece.outstanding_requests, begin)

  case outstanding {
    Ok(block_request) -> {
      use <- bool.guard(
        begin != block_request.begin,
        return: Error(ProtocolError("piece block offset mismatch")),
      )
      let rem = piece.length - begin
      let expected_block_size = case rem > block_size {
        True -> block_size
        False -> rem
      }
      let rx_block_size = bit_array.byte_size(block)
      use <- bool.guard(
        rx_block_size != expected_block_size,
        return: Error(ProtocolError("incomplete block")),
      )

      let outstanding = dict.delete(piece.outstanding_requests, begin)
      let piece =
        Piece(..piece, outstanding_requests: outstanding, blocks: [
          block,
          ..piece.blocks
        ])
      Ok(piece)
    }
    Error(_) -> Ok(piece)
  }
}

fn request_piece(session: PeerSession) -> Result(PeerSession, ProtocolError) {
  let assert Some(piece) = session.piece
  let reqs = piece.remaining_requests |> list.take(4)

  use _ <- try(
    list.try_each(reqs, fn(req) {
      let id = 6
      let request_message = <<
        13:big-size(4)-unit(8),
        id:int,
        piece.index:big-size(4)-unit(8),
        req.begin:big-size(4)-unit(8),
        req.length:big-size(4)-unit(8),
      >>

      mug.send(session.socket, request_message)
      |> map_error(TCPError)
    }),
  )

  let outstanding =
    list.fold(reqs, piece.outstanding_requests, fn(outstanding, req) {
      dict.insert(outstanding, req.begin, req)
    })
  let remaining = list.drop(piece.remaining_requests, 4)
  let new_piece =
    Piece(
      ..piece,
      remaining_requests: remaining,
      outstanding_requests: outstanding,
    )
  Ok(PeerSession(..session, piece: Some(new_piece)))
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
      Ok(PieceMessage(piece_index, begin, block))
    }
    id -> Error(UnknownMessageId(id))
  }
}

fn message_id(message: PeerMessage) -> Int {
  case message {
    Choke -> 0
    Unchoke -> 1
    Interested -> 2
    NotInterested -> 3
    Have -> 4
    BitField(_) -> 5
    Request(_, _, _) -> 6
    PieceMessage(_, _, _) -> 7
  }
}

fn verify_piece(binary: BitArray, hash: BitArray) {
  let calc = crypto.hash(crypto.Sha1, binary)
  case calc == hash {
    True -> Ok(Nil)
    False -> Error(ProtocolError("hashes dont match"))
  }
}

fn piece_length(index: Int, file_length: Int, piece_size: Int) -> Int {
  let piece_count = { file_length + piece_size - 1 } / piece_size
  case piece_count - 1 == index {
    True ->
      case file_length % piece_size {
        0 -> piece_size
        rem -> rem
      }
    False -> piece_size
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

fn request_blocks(length: Int) -> List(BlockRequest) {
  let block_count = { length + block_size - 1 } / block_size
  request_blocks_loop(length, block_count - 1, [])
}

fn request_blocks_loop(
  length: Int,
  block: Int,
  requests: List(BlockRequest),
) -> List(BlockRequest) {
  case block < 0 {
    False -> {
      let begin = block * block_size
      let block_length = int.min(block_size, length - begin)
      let request = BlockRequest(begin: begin, length: block_length)
      request_blocks_loop(length, block - 1, [request, ..requests])
    }
    True -> requests
  }
}

pub type ProtocolError {
  InvalidEndpoint
  InvalidResponse
  InfoHashMismatch
  TCPError(mug.Error)
  UnknownMessageId(Int)
  UnexpectedMessage(Int)
  ProtocolError(String)
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
