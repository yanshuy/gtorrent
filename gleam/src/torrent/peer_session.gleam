import gleam/bit_array
import gleam/bool
import gleam/crypto
import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result.{map_error, replace_error, try}
import mug
import torrent/protocol.{BitField, Choke, Have, Interested, Piece, Unchoke}
import torrent/torrent

pub type PeerSession {
  PeerSession(
    socket: mug.Socket,
    peer_id: protocol.PeerId,
    bit_field: BitArray,
    piece: Option(torrent.PieceDownload),
    choked: Bool,
    interested: Bool,
  )
}

pub fn new_session(endpoint: String) -> PeerSession {
  use socket <- try(protocol.connect(ip4, port) |> map_error(ProtocolError))
  use peer_id <- try(
    protocol.handshake(socket, info_hash, peer_id) |> map_error(ProtocolError),
  )
  PeerSession(
    socket,
    peer_id,
    bit_field: <<0>>,
    piece: None,
    choked: True,
    interested: False,
  )
}

pub fn start(ip4: String, port: Int, coordinator, peer_id, info_hash) {
  let session = new_session(socket, peer_id)
  use bitfield <- try(receive_bitfield(session))

  let session = new_session(socket, peer_id, bitfield)

  process.send(coordinator, Ready(peer_id, bitfield, self()))

  peer_loop(session)
}

pub fn peer_loop(session: PeerSession) -> Result(PeerSession, PeerError) {
  case session {
    PeerSession(piece: None, ..) -> lease_next_piece()
    PeerSession(bit_field: <<0>>, ..) -> {
      use _ <- try(receive_bitfield(session))
      peer_listen(session)
    }
    PeerSession(choked: False, interested: True, ..) -> {
      use _ <- try(request_piece_blocks(session))
      peer_listen(session)
    }
    PeerSession(choked: _, interested: False, ..) -> peer_listen(session)
    PeerSession(choked: True, interested: True, ..) -> peer_listen(session)
  }
}

fn receive_bitfield(session: PeerSession) -> Result(PeerSession, PeerError) {
  use message <- try(
    protocol.receive_message(session.socket) |> result.map_error(ProtocolError),
  )
  case message {
    BitField(bits) -> Ok(PeerSession(..session, bit_field: bits))
    _ -> receive_bitfield(session)
  }
}

fn peer_listen(session: PeerSession) -> Result(PeerSession, PeerError) {
  use message <- try(
    protocol.receive_message(session.socket) |> map_error(ProtocolError),
  )
  echo protocol.log(message)
  case message {
    Choke -> peer_exchange(PeerSession(..session, choked: True))
    Unchoke -> peer_exchange(PeerSession(..session, choked: False))
    Have -> peer_exchange(session)
    BitField(bits) -> handle_bit_field(session, bits)

    Piece(_, _, _) -> {
      use piece <- try(handle_piece_block(session, message))
      case piece.pending_requests {
        [_, ..] -> peer_exchange(session)
        [] -> {
          use _ <- try(handle_piece_complete(piece))
          peer_exchange(PeerSession(..session, piece: None))
        }
      }
    }
    message -> Error(UnexpectedMessage(protocol.message_id(message)))
  }
}

fn handle_piece_complete(piece: torrent.PieceDownload) {
  let data = list.reverse(piece.blocks) |> bit_array.concat
  use _ <- try(verify_piece(data, piece.info.hash))

  todo
}

fn handle_bit_field(
  session: PeerSession,
  bit_field: BitArray,
) -> Result(PeerSession, PeerError) {
  use <- bool.guard(
    is_any_bit_set(session.bit_field),
    return: Error(DuplicateBitfield),
  )
  case is_any_bit_set(bit_field) {
    True -> {
      let id = protocol.message_id(Interested)
      let message = <<1:big-size(4)-unit(8), id:int>>
      use _ <- try(
        protocol.send_message(session.socket, message)
        |> map_error(ProtocolError),
      )
      Ok(PeerSession(..session, interested: True))
    }
    False -> Ok(PeerSession(..session, interested: False))
  }
}

fn request_piece_blocks(
  session: PeerSession,
) -> Result(PeerSession, PeerError) {
  let assert Some(piece) = session.piece
  let reqs = piece.pending_requests |> list.take(4)

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
  let remaining = list.drop(piece.pending_requests, 4)
  let new_piece =
    torrent.PieceDownload(
      ..piece,
      pending_requests: remaining,
      outstanding_requests: outstanding,
    )
  Ok(PeerSession(..session, piece: Some(new_piece)))
}

fn handle_piece_block(
  session: PeerSession,
  message: protocol.PeerMessage,
) -> Result(torrent.PieceDownload, PeerError) {
  let assert Some(piece) = session.piece
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
      let new_blocks = [block, ..piece.blocks]

      torrent.PieceDownload(
        ..piece,
        outstanding_requests: outstanding,
        blocks: new_blocks,
      )
      |> Ok
    }
    Error(_) -> Ok(piece)
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
    PeerError(_) -> todo
    UnexpectedMessage(_) -> todo
    ProtocolError(_) -> todo
    PieceHashMismatch -> todo
    InvalidBlock -> todo
    DuplicateBitfield -> todo
  }
}
