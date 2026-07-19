import bencode
import gleam/bit_array
import gleam/bool
import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/pair
import gleam/result.{map_error, replace_error, try}
import mug
import torrent/messages
import torrent/peer/extension
import torrent/peer/protocol.{
  BitField, Choke, Extension, Handshake, Have, Interested, MetadataPiece, Piece,
  Unchoke,
}
import torrent/torrent

pub type PieceDownload {
  PieceDownload(
    index: Int,
    length: Int,
    blocks: dict.Dict(Int, BitArray),
    pending_requests: List(BlockRequest),
    outstanding_requests: dict.Dict(Int, BlockRequest),
  )
}

pub fn new_piece_download(piece: torrent.PieceInfo) {
  PieceDownload(
    index: piece.index,
    length: piece.length,
    blocks: dict.new(),
    pending_requests: piece_block_requests(piece.length),
    outstanding_requests: dict.new(),
  )
}

pub type State {
  NoPiece
  AwaitLease
  Download(piece: PieceDownload)
}

pub type PeerSession {
  PeerSession(
    socket: mug.Socket,
    peer_id: protocol.PeerId,
    bitfield: Option(BitArray),
    extensions: Option(dict.Dict(String, Int)),
    state: State,
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
    bitfield: None,
    extensions: None,
    state: NoPiece,
    choked: True,
    interested: False,
  )
}

fn extended_handshake(socket, supported) -> Result(Nil, PeerError) {
  case supported {
    True ->
      extension.send_handshake(socket)
      |> map_error(ProtocolError)
    False -> Ok(Nil)
  }
}

pub fn start_session(
  parent_subject: Subject(messages.PeerEvent),
  endpoint: protocol.Endpoint,
  info_hash: BitArray,
  peer_id: protocol.PeerId,
) {
  use #(socket, peer_peer_id, extension_supported) <- try(
    protocol.handshake(endpoint, info_hash, peer_id)
    |> result.map_error(ProtocolError),
  )
  let session = new_session(socket, peer_peer_id)

  use _ <- try(extended_handshake(session.socket, extension_supported))

  let message_subject: Subject(ReaderMessage) = process.new_subject()
  let piece_subject: Subject(torrent.PieceInfo) = process.new_subject()

  process.spawn(fn() { peer_reader(message_subject, session.socket) })

  let result = run(parent_subject, message_subject, piece_subject, session)
  case result {
    Ok(_) -> Nil
    Error(err) -> disconnect(parent_subject, peer_peer_id, err)
  }
  Ok(Nil)
}

type ReaderMessage {
  Message(protocol.PeerMessage)
  ReadError(PeerError)
}

fn peer_reader(message_subject: Subject(ReaderMessage), socket: mug.Socket) {
  let result = protocol.receive_message(socket) |> map_error(ProtocolError)
  case result {
    Ok(message) -> {
      process.send(message_subject, Message(message))
      peer_reader(message_subject, socket)
    }
    Error(err) -> {
      // case err {
      //   ProtocolError(protocol.TCPError(mug.Timeout)) -> {
      //     todo
      //   }
      //   _ -> todo
      // }
      process.send(message_subject, ReadError(err))
    }
  }
}

type SessionMessage {
  PieceLease(torrent.PieceInfo)
  ReaderMessage(ReaderMessage)
}

fn run(
  parent_subject: Subject(messages.PeerEvent),
  message_subject: Subject(ReaderMessage),
  piece_subject: Subject(torrent.PieceInfo),
  session: PeerSession,
) -> Result(Nil, PeerError) {
  let selector =
    process.new_selector()
    |> process.select_map(piece_subject, PieceLease)
    |> process.select_map(message_subject, ReaderMessage)

  case process.selector_receive(selector, 10_000) {
    Ok(event) -> {
      case event {
        PieceLease(info) -> {
          let piece = new_piece_download(info)
          let session = PeerSession(..session, state: Download(piece))
          use session <- try(act(parent_subject, session))
          run(parent_subject, message_subject, piece_subject, session)
        }

        ReaderMessage(Message(message)) -> {
          use session <- try(handle_message(session, message))
          let _ = case message {
            BitField(_) ->
              process.send(
                parent_subject,
                messages.Ready(session.peer_id, piece_subject),
              )
            _ -> Nil
          }
          use session <- try(act(parent_subject, session))
          run(parent_subject, message_subject, piece_subject, session)
        }

        ReaderMessage(ReadError(err)) -> Error(err)
      }
    }
    Error(_) -> Error(PeerError("taking too long"))
  }
}

fn disconnect(
  parent_subject: Subject(messages.PeerEvent),
  peer_id: protocol.PeerId,
  err: PeerError,
) {
  process.send(
    parent_subject,
    messages.PeerDisconnected(peer_id, reason: describe_error(err)),
  )
  process.kill(process.self())
}

// act on session update
fn act(
  parent_subject: Subject(messages.PeerEvent),
  session: PeerSession,
) -> Result(PeerSession, PeerError) {
  case session {
    PeerSession(bitfield: None, ..) -> Ok(session)

    // problem when to send messages.Ready(session.peer_id, piece_subject)
    PeerSession(interested: False, ..) -> send_interested(session)

    PeerSession(choked: True, ..) -> Ok(session)

    PeerSession(state: NoPiece, ..) -> {
      ask_lease(parent_subject, session)
      PeerSession(..session, state: AwaitLease) |> Ok
    }

    PeerSession(state: AwaitLease, ..) -> Ok(session)

    PeerSession(state: Download(piece), ..) ->
      notify_or_progress(parent_subject, session, piece)
  }
}

fn ask_lease(
  parent_subject: Subject(messages.PeerEvent),
  session: PeerSession,
) {
  let assert Some(bitfield) = session.bitfield
    as "idle state before bitfield is set"
  process.send(parent_subject, messages.LeasePiece(session.peer_id, bitfield))
}

fn notify_or_progress(
  parent_subject,
  session: PeerSession,
  piece: PieceDownload,
) -> Result(PeerSession, PeerError) {
  case
    list.is_empty(piece.pending_requests),
    dict.is_empty(piece.outstanding_requests)
  {
    True, True -> {
      handle_piece_complete(parent_subject, session.peer_id, piece)
      ask_lease(parent_subject, session)
      PeerSession(..session, state: NoPiece) |> Ok
    }
    True, False -> Ok(session)
    False, _ -> {
      use piece <- try(request_piece_blocks(session, piece))
      PeerSession(..session, state: Download(piece)) |> Ok
    }
  }
}

fn handle_piece_complete(
  parent_subject: Subject(messages.PeerEvent),
  peer_id: protocol.PeerId,
  piece: PieceDownload,
) {
  // use blocks <- try(                  // production grade
  //   piece_block_requests(piece.length)
  //   |> list.try_map(fn(req) {
  //     dict.get(piece.blocks, req.begin)
  //     |> result.replace_error(InvalidBlock)
  //   }),
  // )
  let blocks =
    dict.to_list(piece.blocks)
    |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
    |> list.map(pair.second)
  let bin = bit_array.concat(blocks)

  let message =
    messages.PieceCompleted(peer: peer_id, index: piece.index, piece: bin)
  process.send(parent_subject, message)
}

fn handle_message(
  session: PeerSession,
  message: protocol.PeerMessage,
) -> Result(PeerSession, PeerError) {
  case message {
    Choke -> PeerSession(..session, choked: True) |> Ok
    Unchoke -> PeerSession(..session, choked: False) |> Ok
    Have -> Ok(session)

    BitField(bitfield) -> {
      case session.bitfield {
        Some(_) -> Error(DuplicateBitfield)
        None -> PeerSession(..session, bitfield: Some(bitfield)) |> Ok
      }
    }

    Extension(message) -> handle_extension_message(session, message) |> Ok

    Piece(_, _, _) -> {
      case session.state {
        Download(piece) -> {
          use piece <- try(handle_piece_block(message, piece))
          PeerSession(..session, state: Download(piece)) |> Ok
        }
        _ -> Error(UnexpectedMessage(protocol.message_id(message)))
      }
    }

    _ -> Error(UnexpectedMessage(protocol.message_id(message)))
  }
}

fn handle_extension_message(session, message: protocol.ExtensionMessage) {
  case message {
    protocol.Handshake(extensions) -> {
      let extensions = dict.from_list(extensions)
      PeerSession(..session, extensions: Some(extensions))
    }
    protocol.MetadataPiece(piece_index, piece) -> todo
    protocol.MetadataRequest(piece_index:) -> todo
  }
}

fn send_interested(session: PeerSession) -> Result(PeerSession, PeerError) {
  let assert Some(bitfield) = session.bitfield as "Bitfield not set"
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

pub type BlockRequest {
  BlockRequest(begin: Int, length: Int)
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
        piece.index:big-size(4)-unit(8),
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
    peer_piece_index != piece.index,
    return: Error(PeerError("piece index mismatch")),
  )
  let outstanding = dict.get(piece.outstanding_requests, begin)

  case outstanding {
    Ok(_) -> {
      let rem = piece.length - begin
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
    Error(_) -> Ok(piece)
  }
}

pub fn is_any_bit_set(bitfield: BitArray) -> Bool {
  case bitfield {
    <<byte:int, rest:bits>> -> byte != 0 || is_any_bit_set(rest)
    <<>> | _ -> False
  }
}

pub fn download_piece(
  session: PeerSession,
  piece: torrent.Piece,
) -> Result(#(BitArray, torrent.PieceInfo), PeerError) {
  use session <- try(receive_bitfield(session))

  use #(session, piece_info) <- try(case piece {
    torrent.Piece(piece) -> #(session, piece) |> Ok
    torrent.PieceIndex(idx) -> {
      use #(session, extensions) <- try(extension_handshake(session))
      use #(session, metadata) <- try(extension_metadata(session, extensions))
      use torrent <- try(
        torrent.from_metadata(metadata, <<>>) |> map_error(DecodeError),
      )
      use piece <- try(
        torrent.new_pieces(torrent.length, torrent.piece_length, torrent.pieces)
        |> list.drop(idx)
        |> list.first
        |> replace_error(PeerError("invalid piece index")),
      )
      #(session, piece) |> Ok
    }
  })

  use session <- try(send_interested(session))
  use session <- try(wait_unchoke(session))

  let piece = new_piece_download(piece_info)
  use piece <- try(request_piece_blocks(session, piece))
  use piece <- try(receive_all_blocks(session, piece))

  let blocks =
    dict.to_list(piece.blocks)
    |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
    |> list.map(pair.second)

  let data = bit_array.concat(blocks)
  #(data, piece_info) |> Ok
}

pub fn extension_handshake(session: PeerSession) {
  use _ <- try(
    extension.send_handshake(session.socket)
    |> map_error(ProtocolError),
  )

  let is_handshake = fn(message) {
    case message {
      Extension(Handshake(..)) -> True
      _ -> False
    }
  }
  use #(session, message) <- try(receive_until(session, is_handshake))

  let assert Extension(Handshake(extensions)) = message
  #(session, extensions) |> Ok
}

pub fn extension_metadata(
  session: PeerSession,
  extensions: List(#(String, Int)),
) {
  use extension_id <- try(
    list.key_find(extensions, "ut_metadata")
    |> replace_error(PeerError("ut_metadata extension not supported by peer")),
  )
  use _ <- try(
    extension.send_metadata_request(session.socket, extension_id)
    |> map_error(ProtocolError),
  )
  let is_metadata_piece = fn(message) {
    case message {
      Extension(MetadataPiece(..)) -> True
      _ -> False
    }
  }
  use #(session, message) <- try(receive_until(session, is_metadata_piece))

  let assert Extension(MetadataPiece(_, piece)) = message
  use bencode <- try(bencode.decode(piece) |> map_error(DecodeError))
  #(session, bencode) |> Ok
}

pub fn receive_bitfield(
  session: PeerSession,
) -> Result(PeerSession, PeerError) {
  use message <- try(
    protocol.receive_message(session.socket) |> result.map_error(ProtocolError),
  )
  case message {
    BitField(bits) -> PeerSession(..session, bitfield: Some(bits)) |> Ok
    // for now if no bitfield sent just disconnect
    _ -> Error(PeerError("no bitfield"))
  }
}

pub fn wait_unchoke(session: PeerSession) -> Result(PeerSession, PeerError) {
  case session.choked {
    True -> {
      receive_until(session, fn(message) {
        case message {
          Unchoke -> True
          _ -> False
        }
      })
      |> result.map(pair.first)
    }
    False -> Ok(session)
  }
}

fn receive_all_blocks(
  session: PeerSession,
  piece: PieceDownload,
) -> Result(PieceDownload, PeerError) {
  case
    list.is_empty(piece.pending_requests),
    dict.is_empty(piece.outstanding_requests)
  {
    True, True -> Ok(piece)
    _, _ -> {
      use message <- try(
        protocol.receive_message(session.socket) |> map_error(ProtocolError),
      )
      case message {
        Piece(_, _, _) -> {
          use piece <- try(handle_piece_block(message, piece))
          use piece <- try(request_piece_blocks(session, piece))
          receive_all_blocks(session, piece)
        }
        _ -> receive_all_blocks(session, piece)
      }
    }
  }
}

pub fn receive_until(
  session: PeerSession,
  stop: fn(protocol.PeerMessage) -> Bool,
) -> Result(#(PeerSession, protocol.PeerMessage), PeerError) {
  use rx_message <- try(
    protocol.receive_message(session.socket) |> map_error(ProtocolError),
  )
  use session <- try(handle_message(session, rx_message))

  case stop(rx_message) {
    True -> #(session, rx_message) |> Ok
    False -> receive_until(session, stop)
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

pub type PeerError {
  InvalidBlock
  DuplicateBitfield
  UnexpectedMessage(Int)
  PeerError(String)
  ProtocolError(protocol.ProtocolError)
  DecodeError(bencode.BencodeError)
}

pub fn describe_error(error: PeerError) -> String {
  case error {
    PeerError(reason) -> "Peer error: " <> reason
    UnexpectedMessage(id) -> "Unexpected message ID: " <> int.to_string(id)
    ProtocolError(err) -> protocol.describe_error(err)
    InvalidBlock -> "Received an invalid data block length, offset, or payload"
    DuplicateBitfield ->
      "Protocol violation: peer sent a second bitfield message"
    DecodeError(err) -> bencode.describe_error(err)
  }
}
