import gleam/bit_array
import gleam/bool
import gleam/crypto
import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result.{map_error, replace_error, try}
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

pub type PeerSession {
  PeerSession(
    socket: mug.Socket,
    peer_id: protocol.PeerId,
    bitfield: BitArray,
    piece: Option(PieceDownload),
    choked: Bool,
    interested: Bool,
  )
}

pub fn new_session(
  socket: mug.Socket,
  peer_id: protocol.PeerId,
) -> PeerSession {
  PeerSession(
    socket,
    peer_id,
    bitfield: <<>>,
    piece: None,
    choked: True,
    interested: False,
  )
}

pub fn start_session(
  parent_subject: Subject(messages.PeerEvent),
  socket: mug.Socket,
  peer_id: protocol.PeerId,
) {
  let session = new_session(socket, peer_id)
  use session <- try(receive_bitfield(session))

  let piece =
    process.call(parent_subject, 1000, fn(subject) {
      messages.Ready(
        peer: session.peer_id,
        bitfield: session.bitfield,
        reply_subject: subject,
      )
    })
  let piece_dwnld = new_piece_download(piece)
  handle_piece_download(parent_subject, session, piece_dwnld)
  Ok(Nil)
}

fn handle_piece_download(
  parent_subject: Subject(messages.PeerEvent),
  session: PeerSession,
  piece: PieceDownload,
) {
  let session_with_piece = PeerSession(..session, piece: Some(piece))
  let data = handle_piece(session_with_piece)
  let protocol.PeerId(id) = session.peer_id
  echo #("A COMPLETE", id |> bit_array.base16_encode, piece.info.index)
  case data {
    Ok(data) -> {
      process.send(
        parent_subject,
        messages.PieceCompleted(index: piece.info.index, data: data),
      )
      let next_piece =
        process.call_forever(parent_subject, fn(subject) {
          messages.LeasePiece(session.peer_id, subject)
        })
      echo "3 GOT NEXT PIECE"
      let piece_dwnld = new_piece_download(next_piece)
      handle_piece_download(parent_subject, session, piece_dwnld)
    }
    Error(err) -> {
      process.send(
        parent_subject,
        messages.PeerDisconnected(session.peer_id, reason: describe_error(err)),
      )
      process.kill(process.self())
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

fn handle_piece(session: PeerSession) -> Result(BitArray, PeerError) {
  case session {
    PeerSession(piece: None, ..) -> panic as "piece not set before start"
    PeerSession(choked: False, interested: True, ..) -> {
      use session <- try(request_piece_blocks(session))
      peer_listen(session)
    }
    PeerSession(choked: _, interested: False, ..) -> peer_listen(session)
    PeerSession(choked: True, interested: True, ..) -> peer_listen(session)
  }
}

fn peer_listen(session: PeerSession) -> Result(BitArray, PeerError) {
  io.println("[WAIT]")
  use message <- try(
    protocol.receive_message(session.socket) |> map_error(ProtocolError),
  )
  case message {
    Choke -> handle_piece(PeerSession(..session, choked: True))
    Unchoke -> handle_piece(PeerSession(..session, choked: False))
    Have -> handle_piece(session)

    BitField(_) -> Error(DuplicateBitfield)

    Piece(_, _, _) -> {
      use piece <- try(handle_piece_block(session, message))
      case
        list.is_empty(piece.pending_requests)
        && dict.is_empty(piece.outstanding_requests)
      {
        True -> handle_piece_complete(piece)
        False -> {
          let session = PeerSession(..session, piece: Some(piece))
          handle_piece(session)
        }
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
    False -> Error(PeerError("they have nothing"))
  }
}

fn request_piece_blocks(
  session: PeerSession,
) -> Result(PeerSession, PeerError) {
  let assert Some(piece) = session.piece
  echo list.length(piece.pending_requests)
  echo dict.size(piece.outstanding_requests)
  let take = int.min(4, 4 - dict.size(piece.outstanding_requests))
  let remaining = list.drop(piece.pending_requests, take)
  io.println(
    "[REQUEST] piece="
    <> int.to_string(piece.info.index)
    <> " pending="
    <> int.to_string(list.length(piece.pending_requests))
    <> " outstanding="
    <> int.to_string(dict.size(piece.outstanding_requests)),
  )

  let reqs = piece.pending_requests |> list.take(take)
  use _ <- try(
    list.try_each(reqs, fn(req) {
      io.println(
        "[SEND] piece="
        <> int.to_string(piece.info.index)
        <> " begin="
        <> int.to_string(req.begin),
      )
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
  let new_piece =
    PieceDownload(
      ..piece,
      pending_requests: remaining,
      outstanding_requests: outstanding,
    )
  Ok(PeerSession(..session, piece: Some(new_piece)))
}

fn handle_piece_block(
  session: PeerSession,
  message: protocol.PeerMessage,
) -> Result(PieceDownload, PeerError) {
  let assert Some(piece) = session.piece
  let assert Piece(peer_piece_index, begin, block) = message
  io.println(
    "[RECV] piece="
    <> int.to_string(peer_piece_index)
    <> " begin="
    <> int.to_string(begin),
  )
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
      io.println(
        "[STATE] outstanding="
        <> int.to_string(dict.size(outstanding))
        <> " pending="
        <> int.to_string(list.length(piece.pending_requests)),
      )
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
  let session = new_session(socket, peer_id)
  use session <- try(receive_bitfield(session))
  let piece = new_piece_download(piece)
  let session = PeerSession(..session, piece: Some(piece))
  handle_piece(session)
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

    UnexpectedMessage(id) ->
      "Received an unexpected protocol message ID: " <> int.to_string(id)

    ProtocolError(protocol_err) ->
      "BitTorrent protocol validation failed: "
      <> protocol.describe_error(protocol_err)

    PieceHashMismatch ->
      "Data integrity check failed: downloaded piece hash does not match the torrent file info-hash"

    InvalidBlock ->
      "Received an invalid data block length, offset, or payload structural format"

    DuplicateBitfield ->
      "Protocol violation: peer attempted to send a duplicate bitfield message after connection setup"
  }
}
