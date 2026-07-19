import file_io
import gleam/bit_array
import gleam/bool
import gleam/crypto
import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/io
import gleam/list
import gleam/result.{try}
import simplifile
import torrent/peer/protocol
import torrent/peer/session.{
  LeasePiece, Metadata, PeerDisconnected, PieceCompleted, Ready,
  ReturnPieceLease,
}
import torrent/torrent

pub type TorrentState {
  NoTorrent(
    download_path: String,
    peers: dict.Dict(protocol.PeerId, process.Subject(torrent.PieceInfo)),
  )
  Download(
    info: torrent.TorrentInfo,
    pending_pieces: List(torrent.PieceInfo),
    leased_pieces: List(torrent.PieceInfo),
    peers: dict.Dict(protocol.PeerId, process.Subject(torrent.PieceInfo)),
  )
}

fn new_download(
  torrent: torrent.TorrentInfo,
  peers: dict.Dict(protocol.PeerId, Subject(torrent.PieceInfo)),
) {
  let pieces =
    torrent.new_pieces(torrent.length, torrent.piece_length, torrent.pieces)
  Download(
    info: torrent,
    pending_pieces: pieces,
    leased_pieces: [],
    peers: peers,
  )
}

pub type Torrent {
  Torrent(torrent.TorrentInfo)
  Magnet(info_hash: BitArray)
}

pub fn download_torrent(
  download_path: String,
  endpoints: List(protocol.Endpoint),
  torrent: Torrent,
  peer_id: protocol.PeerId,
) -> Result(Nil, TorrentError) {
  let subject: Subject(session.PeerEvent) = process.new_subject()

  case torrent {
    Torrent(info) -> {
      let hash = info.info_hash
      connect_with_peers(subject, endpoints, hash, peer_id, session.NoPiece)
      let writer = file_io.new_file_writer(download_path, info.length)
      handle_download(writer, new_download(info, dict.new()), subject)
    }
    Magnet(info_hash) -> {
      connect_with_peers(subject, endpoints, info_hash, peer_id, session.NoMeta)

      let state = NoTorrent(download_path, dict.new())
      use #(state, info) <- try(handle_metadata(state, subject))
      let assert NoTorrent(..) = state

      let writer = file_io.new_file_writer(download_path, info.length)
      let state =
        new_download(
          torrent.TorrentInfo(..info, info_hash: info_hash),
          state.peers,
        )

      handle_download(writer, state, subject)
    }
  }
}

fn handle_metadata(
  state: TorrentState,
  mailbox: process.Subject(session.PeerEvent),
) {
  let assert NoTorrent(..) = state
  case process.receive(mailbox, within: 10_000) {
    Ok(event) -> {
      case event {
        Ready(peer_id, subject) -> {
          let peers = dict.insert(state.peers, peer_id, subject)
          let state = NoTorrent(..state, peers: peers)
          handle_metadata(state, mailbox)
        }

        Metadata(info) -> #(state, info) |> Ok

        PeerDisconnected(peer_id, reason) -> {
          let id = {
            let protocol.PeerId(id) = peer_id
            id |> bit_array.base16_encode
          }
          io.print_error(
            "Stopping peer session with: " <> id <> "\nReason: " <> reason,
          )
          let peers = dict.delete(state.peers, peer_id)
          let new_state = NoTorrent(..state, peers: peers)
          handle_metadata(new_state, mailbox)
        }
        _ -> handle_metadata(state, mailbox)
      }
    }
    Error(_) -> Error(NoPeerResponding)
  }
}

fn handle_download(
  writer: file_io.Writer,
  state: TorrentState,
  mailbox: process.Subject(session.PeerEvent),
) -> Result(Nil, TorrentError) {
  let assert Download(..) = state
  use <- bool.guard(
    state.pending_pieces |> list.is_empty
      && state.leased_pieces |> list.is_empty,
    return: Ok(Nil),
  )
  case process.receive(mailbox, within: 10_000) {
    Ok(event) -> {
      case event {
        Ready(peer_id, subject) -> {
          let peers = dict.insert(state.peers, peer_id, subject)
          let state = Download(..state, peers: peers)
          handle_download(writer, state, mailbox)
        }

        LeasePiece(peer_id, bitfield) -> {
          let assert Ok(subject) = dict.get(state.peers, peer_id)

          case lease_piece(state, bitfield) {
            Ok(piece) -> {
              process.send(subject, piece)

              let pendings =
                state.pending_pieces
                |> list.filter(fn(pending) { pending.index != piece.index })
              let state = Download(..state, pending_pieces: pendings)

              let leased = [piece, ..state.leased_pieces]
              let state = Download(..state, leased_pieces: leased)

              handle_download(writer, state, mailbox)
            }
            Error(_) -> handle_download(writer, state, mailbox)
          }
        }

        PieceCompleted(_peer_id, index, data) -> {
          io.println("[COMPLETE EVENT] index=" <> int.to_string(index))

          let assert Ok(leased) =
            state.leased_pieces |> list.find(fn(piece) { piece.index == index })
            as "got a piece that was never leased"

          let new_leased =
            state.leased_pieces
            |> list.filter(fn(piece) { piece.index != index })

          case verify_piece(data, leased.hash) {
            True -> {
              process.spawn(fn() {
                let offset = index * state.info.piece_length
                let res = writer.write(writer, offset, data)
                case res {
                  Ok(_) -> Nil
                  Error(_) -> panic as "write failed"
                }
              })

              let new_state = Download(..state, leased_pieces: new_leased)
              handle_download(writer, new_state, mailbox)
            }
            False -> {
              let new_state =
                Download(..state, leased_pieces: new_leased, pending_pieces: [
                  leased,
                  ..state.pending_pieces
                ])
              handle_download(writer, new_state, mailbox)
            }
          }
        }

        ReturnPieceLease(_peer_id, piece_index) -> {
          let assert Ok(leased) =
            state.leased_pieces
            |> list.find(fn(piece) { piece.index == piece_index })
            as "returned a piece that was never leased"

          let new_leased =
            state.leased_pieces
            |> list.filter(fn(piece) { piece.index != piece_index })

          let new_state =
            Download(
              ..state,
              pending_pieces: [leased, ..state.pending_pieces],
              leased_pieces: new_leased,
            )
          handle_download(writer, new_state, mailbox)
        }

        PeerDisconnected(peer_id, reason) -> {
          let id = {
            let protocol.PeerId(id) = peer_id
            id |> bit_array.base16_encode
          }
          io.print_error(
            "Stopping peer session with: " <> id <> "\nReason: " <> reason,
          )
          let peers = dict.delete(state.peers, peer_id)
          let new_state = Download(..state, peers: peers)
          handle_download(writer, new_state, mailbox)
        }

        Metadata(torrent) -> todo
      }
    }
    Error(_) -> Error(NoPeerResponding)
  }
}

pub fn connect_with_peers(
  main_subject: process.Subject(session.PeerEvent),
  endpoints: List(protocol.Endpoint),
  info_hash: BitArray,
  peer_id: protocol.PeerId,
  start_state: session.State,
) {
  let worker_func = fn(endpoint: protocol.Endpoint) {
    let result = {
      use #(socket, peer_peer_id) <- try(
        protocol.handshake(endpoint, info_hash, peer_id)
        |> result.map_error(ProtocolError),
      )
      let session = session.new_session(socket, peer_peer_id, start_state)

      let piece_subject: Subject(torrent.PieceInfo) = process.new_subject()
      process.send(main_subject, Ready(session.peer_id, piece_subject))

      session.run_session(main_subject, piece_subject, session)
      |> result.map_error(PeerError)
    }
    case result {
      Ok(_) -> Nil
      Error(err) ->
        io.println(endpoint.ip4 <> "is malicious" <> describe_error(err))
    }
  }

  endpoints
  |> list.take(6)
  |> list.each(fn(endpoint) { process.spawn(fn() { worker_func(endpoint) }) })
}

fn lease_piece(
  state: TorrentState,
  bitfield: BitArray,
) -> Result(torrent.PieceInfo, Nil) {
  let assert Download(..) = state
  state.pending_pieces
  |> list.find(fn(piece) { is_bit_set(bitfield, piece.index) })
}

// fn print_bits(bits: BitArray, log: List(Int)) {
//   case bits {
//     <<bit:size(1), rest:bits>> if bit == 1 -> print_bits(rest, [1, ..log])
//     <<bit:size(1), rest:bits>> if bit == 0 -> print_bits(rest, [0, ..log])
//     <<>> | _ -> list.reverse(log)
//   }
// }

pub fn is_bit_set(bits: BitArray, index: Int) -> Bool {
  case bits {
    <<_:size(index), target:size(1), _:bits>> -> target == 1
    _ -> False
  }
}

pub fn download_piece(
  download_path: String,
  piece: torrent.Piece,
  session: session.PeerSession,
) -> Result(Nil, TorrentError) {
  use #(data, piece) <- try(
    session.download_piece(session, piece)
    |> result.map_error(PeerError),
  )

  case verify_piece(data, piece.hash) {
    True -> {
      let writer = file_io.new_file_writer(download_path, piece.length)

      writer.write(writer, 0, data)
      |> result.replace_error(FileError(simplifile.Efault))
    }
    False -> Error(TorrentError("piece hash mismatch"))
  }
}

fn verify_piece(binary: BitArray, hash: BitArray) {
  let calc = crypto.hash(crypto.Sha1, binary)
  calc == hash
}

pub type TorrentError {
  NoPeerResponding
  ProtocolError(protocol.ProtocolError)
  PeerError(session.PeerError)
  FileError(simplifile.FileError)
  TorrentError(String)
}

pub fn describe_error(error: TorrentError) -> String {
  case error {
    NoPeerResponding ->
      "Torrent download stalled: No connected peers are currently responding to download requests"
    ProtocolError(err) ->
      "Torrent protocol error: " <> protocol.describe_error(err)
    PeerError(err) -> session.describe_error(err)
    FileError(file_err) ->
      "Disk I/O error: " <> simplifile.describe_error(file_err)
    TorrentError(reason) -> reason
  }
}
