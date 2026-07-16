import gleam/bit_array
import gleam/bool
import gleam/crypto
import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result.{map_error, try}
import mug
import torrent/messages
import torrent/peer/protocol.{BitField, Choke, Have, Interested, Piece, Unchoke}
import torrent/torrent

pub type PieceDownload {
  PieceDownload(
    info: torrent.PieceInfo,
    blocks: dict.Dict(Int, BitArray),
    pending_requests: List(BlockRequest),
    outstanding_requests: dict.Dict(Int, BlockRequest),
  )
}

pub fn new_piece_download(piece: torrent.PieceInfo) {
  PieceDownload(
    info: piece,
    blocks: dict.new(),
    pending_requests: piece_block_requests(piece.length),
    outstanding_requests: dict.new(),
  )
}

pub type State {
  Bitfield
  ExtHandshake
  Idle
  Download(PieceDownload)
}

pub type PeerSession {
  PeerSession(
    socket: mug.Socket,
    peer_id: protocol.PeerId,
    extension: Bool,
    state: State,
    bitfield: BitArray,
    choked: Bool,
    interested: Bool,
  )
}

pub fn new_session(
  socket: mug.Socket,
  peer_id: protocol.PeerId,
  extension: Bool,
) -> PeerSession {
  PeerSession(
    socket,
    peer_id,
    extension: extension,
    state: Bitfield,
    bitfield: <<>>,
    choked: True,
    interested: False,
  )
}

fn run(
  parent_subject: Subject(messages.PeerEvent),
  session: PeerSession,
  need_meta: Bool,
) {
  case session.state {
    Bitfield -> {
      use session <- try(receive_bitfield(session))
      process.send(
        parent_subject,
        messages.Ready(session.peer_id, session.bitfield),
      )
      case need_meta {
        True -> {
          let session = PeerSession(..session, state: ExtHandshake)
          run(parent_subject, session, need_meta)
        }
        False ->
          run(parent_subject, PeerSession(..session, state: Idle), need_meta)
      }
    }

    ExtHandshake -> {
      use _ <- try(
        protocol.extension_handshake(session.socket) |> map_error(ProtocolError),
      )
      run(parent_subject, PeerSession(..session, state: Idle), need_meta)
    }

    Idle -> {
      let piece_dwnld = wait_for_lease(parent_subject, session)
      let session = PeerSession(..session, state: Download(piece_dwnld))
      run(parent_subject, session, need_meta)
    }

    Download(piece) -> {
      let session = handle_piece_download(parent_subject, session, piece)
      run(parent_subject, PeerSession(..session, state: Idle), need_meta)
    }
  }
}

fn wait_for_lease(
  parent_subject: Subject(messages.PeerEvent),
  session: PeerSession,
) -> PieceDownload {
  let piece =
    process.call_forever(parent_subject, fn(subject) {
      messages.LeasePiece(session.peer_id, subject)
    })
  new_piece_download(piece)
}

pub fn start_session(
  parent_subject: Subject(messages.PeerEvent),
  endpoint: protocol.Endpoint,
  info_hash: BitArray,
  peer_id: protocol.PeerId,
) {
  use #(socket, peer_peer_id, extension) <- try(
    protocol.handshake(endpoint, info_hash, peer_id)
    |> result.map_error(ProtocolError),
  )
  let session = new_session(socket, peer_peer_id, extension)
  let _ = run(parent_subject, session, False)
  Ok(Nil)
}

fn handle_piece_download(
  parent_subject: Subject(messages.PeerEvent),
  session: PeerSession,
  piece_download: PieceDownload,
) -> PeerSession {
  let result = request_piece(session, piece_download)
  case result {
    Ok(#(session, piece)) -> {
      process.send(
        parent_subject,
        messages.PieceCompleted(index: piece_download.info.index, piece: piece),
      )
      session
    }
    Error(err) -> {
      process.send(
        parent_subject,
        messages.PeerDisconnected(session.peer_id, reason: describe_error(err)),
      )
      process.kill(process.self())
      session
    }
  }
}

fn receive_bitfield(session: PeerSession) -> Result(PeerSession, PeerError) {
  use message <- try(
    protocol.receive_message(session.socket) |> result.map_error(ProtocolError),
  )
  case message {
    BitField(bits) ->
      handle_bitfield(PeerSession(..session, bitfield: bits), bits)
    // for now if no bitfield sent just disconnect
    _ -> Error(PeerError("no bitfield"))
  }
}

pub type BlockRequest {
  BlockRequest(begin: Int, length: Int)
}

fn request_piece(
  session: PeerSession,
  piece: PieceDownload,
) -> Result(#(PeerSession, BitArray), PeerError) {
  case session {
    PeerSession(choked: False, interested: True, ..) -> {
      use new_piece <- try(request_piece_blocks(session, piece))
      peer_listen(session, new_piece)
    }
    PeerSession(choked: _, interested: False, ..) -> peer_listen(session, piece)
    PeerSession(choked: True, interested: True, ..) ->
      peer_listen(session, piece)
  }
}

fn peer_listen(
  session: PeerSession,
  piece: PieceDownload,
) -> Result(#(PeerSession, BitArray), PeerError) {
  use message <- try(
    protocol.receive_message(session.socket) |> map_error(ProtocolError),
  )
  case message {
    Choke -> request_piece(PeerSession(..session, choked: True), piece)
    Unchoke -> request_piece(PeerSession(..session, choked: False), piece)
    Have -> request_piece(session, piece)

    BitField(_) -> Error(DuplicateBitfield)

    Piece(_, _, _) -> {
      use piece <- try(handle_piece_block(message, piece))
      case
        list.is_empty(piece.pending_requests)
        && dict.is_empty(piece.outstanding_requests)
      {
        True -> {
          use piece <- try(handle_piece_complete(piece))
          #(session, piece) |> Ok
        }
        False -> request_piece(session, piece)
      }
    }
    message -> Error(UnexpectedMessage(protocol.message_id(message)))
  }
}

fn handle_piece_complete(piece: PieceDownload) -> Result(BitArray, PeerError) {
  use blocks <- try(
    piece_block_requests(piece.info.length)
    |> list.try_map(fn(req) {
      dict.get(piece.blocks, req.begin)
      |> result.replace_error(InvalidBlock)
    }),
  )

  let data = bit_array.concat(blocks)
  use _ <- try(verify_piece(data, piece.info.hash))
  Ok(data)
}

fn handle_bitfield(
  session: PeerSession,
  bitfield: BitArray,
) -> Result(PeerSession, PeerError) {
  case is_any_bit_set(bitfield) {
    True -> {
      let id = protocol.message_id(Interested)
      let message = <<1:big-size(4)-unit(8), id:int>>
      use _ <- try(
        protocol.send_message(session.socket, message)
        |> map_error(ProtocolError),
      )
      Ok(PeerSession(..session, interested: True))
    }
    False -> Error(PeerError("peer has nothing"))
  }
}

fn request_piece_blocks(
  session: PeerSession,
  piece: PieceDownload,
) -> Result(PieceDownload, PeerError) {
  let take = int.min(4, 4 - dict.size(piece.outstanding_requests))
  let remaining = list.drop(piece.pending_requests, take)

  let reqs = piece.pending_requests |> list.take(take)
  use _ <- try(
    list.try_each(reqs, fn(req) {
      let id = 6
      let request_message = <<
        13:big-size(4)-unit(8),
        id:int,
        piece.info.index:big-size(4)-unit(8),
        req.begin:big-size(4)-unit(8),
        req.length:big-size(4)-unit(8),
      >>

      protocol.send_message(session.socket, request_message)
      |> map_error(ProtocolError)
    }),
  )

  let outstanding =
    list.fold(reqs, piece.outstanding_requests, fn(outstanding, req) {
      dict.insert(outstanding, req.begin, req)
    })

  PieceDownload(
    ..piece,
    pending_requests: remaining,
    outstanding_requests: outstanding,
  )
  |> Ok
}

fn handle_piece_block(
  message: protocol.PeerMessage,
  piece: PieceDownload,
) -> Result(PieceDownload, PeerError) {
  let assert Piece(peer_piece_index, begin, block) = message
  use <- bool.guard(
    peer_piece_index != piece.info.index,
    return: Error(PeerError("piece index mismatch")),
  )
  let outstanding = dict.get(piece.outstanding_requests, begin)

  case outstanding {
    Ok(block_request) -> {
      use <- bool.guard(
        begin != block_request.begin,
        return: Error(PeerError("piece block offset mismatch")),
      )
      let rem = piece.info.length - begin
      let expected_block_size = case rem > torrent.block_size {
        True -> torrent.block_size
        False -> rem
      }
      let rx_block_size = bit_array.byte_size(block)
      use <- bool.guard(
        rx_block_size != expected_block_size,
        return: Error(PeerError("incomplete block")),
      )

      let outstanding = dict.delete(piece.outstanding_requests, begin)
      let new_blocks = dict.insert(piece.blocks, begin, block)

      PieceDownload(
        ..piece,
        outstanding_requests: outstanding,
        blocks: new_blocks,
      )
      |> Ok
    }
    Error(_) -> Error(InvalidBlock)
  }
}

fn verify_piece(binary: BitArray, hash: BitArray) {
  let calc = crypto.hash(crypto.Sha1, binary)
  case calc == hash {
    True -> Ok(Nil)
    False -> Error(PieceHashMismatch)
  }
}

pub fn is_any_bit_set(bitfield: BitArray) -> Bool {
  case bitfield {
    <<byte:int, rest:bits>> -> byte != 0 || is_any_bit_set(rest)
    <<>> | _ -> False
  }
}

pub fn piece_block_requests(piece_length: Int) -> List(BlockRequest) {
  let block_count =
    { piece_length + torrent.block_size - 1 } / torrent.block_size
  piece_block_requests_loop(piece_length, block_count - 1, [])
}

fn piece_block_requests_loop(
  length: Int,
  block: Int,
  requests: List(BlockRequest),
) -> List(BlockRequest) {
  case block < 0 {
    False -> {
      let begin = block * torrent.block_size
      let block_length = int.min(torrent.block_size, length - begin)
      let request = BlockRequest(begin: begin, length: block_length)
      piece_block_requests_loop(length, block - 1, [request, ..requests])
    }
    True -> requests
  }
}

pub fn download_piece(
  socket: mug.Socket,
  peer_id: protocol.PeerId,
  piece: torrent.PieceInfo,
) -> Result(BitArray, PeerError) {
  let session = new_session(socket, peer_id, False)
  use session <- try(receive_bitfield(session))
  let piece = new_piece_download(piece)
  use result <- try(request_piece(session, piece))
  result.1 |> Ok
}

pub type PeerError {
  PeerError(String)
  UnexpectedMessage(Int)
  ProtocolError(protocol.ProtocolError)
  PieceHashMismatch
  InvalidBlock
  DuplicateBitfield
}

pub fn describe_error(error: PeerError) -> String {
  case error {
    PeerError(reason) -> "Peer connection error: " <> reason
    UnexpectedMessage(id) -> "Unexpected message ID: " <> int.to_string(id)
    ProtocolError(protocol_err) -> protocol.describe_error(protocol_err)
    PieceHashMismatch ->
      "downloaded piece hash does not match the torrent file info-hash"
    InvalidBlock -> "Received an invalid data block length, offset, or payload"
    DuplicateBitfield ->
      "Protocol violation: peer sent a second bitfield message"
  }
}
