import gleam/dict
import gleam/erlang/process
import simplifile
import torrent/file_io
import torrent/messages.{PeerDisconnected, PieceCompleted, Ready}
import torrent/peer/peer_session
import torrent/peer/protocol
import torrent/torrent

pub type DownloadState {
  DownloadState(
    torrent: torrent.TorrentInfo,
    peers: dict.Dict(protocol.PeerId, process.Subject(messages.WorkerCmd)),
  )
}

fn downlaod(
  state: DownloadState,
  writer: file_io.Writer,
  mailbox: process.Subject(messages.PeerEvent),
) -> Result(DownloadState, TorrentError) {
  case process.receive(mailbox, within: 5000) {
    Ok(event) -> {
      case event {
        Ready(peer_id, worker, _bitfield) -> {
          let peers = dict.insert(state.peers, peer_id, worker)
          let state = DownloadState(..state, peers: peers)
          process.send(worker, messages.AssignPiece(piece))
          downlaod(state, writer, mailbox)
        }
        PieceCompleted(peer_id, index, data) -> {
          let offset = index * torrent.block_size
          process.spawn(fn() { writer.write(offset, data) })
          state |> Ok
        }
        PeerDisconnected(_) -> {
          todo
        }
      }
    }
    Error(_) -> todo
  }
}

pub type TorrentError {
  PeerError(peer_session.PeerError)
  FileError(simplifile.FileError)
}
// fn assign_pieces(
//   pieces: List(Piece),
//   sessions: List(PeerSession),
// ) -> List(PeerSession) {
//   keep_assigning(pieces, sessions, [])
// }

// fn keep_assigning(
//   pieces: List(Piece),
//   sessions: List(PeerSession),
//   new_sessions: List(PeerSession),
// ) -> List(PeerSession) {
//   case sessions, pieces {
//     [], _ -> new_sessions
//     _, [] -> new_sessions
//     [session, ..sessions], [piece, ..pieces] -> {
//       let new_sessions = [
//         PeerSession(..session, piece: Some(new_piece_download(piece))),
//         ..sessions
//       ]
//       keep_assigning(pieces, sessions, new_sessions)
//     }
//   }
// }
