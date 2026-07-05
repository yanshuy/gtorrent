import gleam/erlang/process
import simplifile
import torrent/file_io
import torrent/torrent

// import torrent/peer_session
import torrent/protocol

pub type DownloadState {
  DownloadState(
    torrent: torrent.TorrentInfo,
    peers: dict.Dict(protocol.PeerId, process.Subject(peer_session.WorkerCmd)),
    writer: file_io.Writer,
  )
}

pub type PeerEvent {
  Ready(peer: protocol.PeerId, worker: process.Subject(peer_session.WorkerCmd))
  PieceCompleted(peer: protocol.PeerId, index: Int, data: BitArray)
  PeerDisconnected(protocol.PeerId)
}

fn downlaod(
  state: DownloadState,
  mailbox: process.Subject(PeerEvent),
) -> Result(Nil, TorrentError) {
  //wait for mailbox

  case process.receive(mailbox, within: 5000) {
    Ok(event) -> {
      case event {
        Ready(peer:, worker:) -> todo
        PieceCompleted(peer:, index:, data:) -> todo
        PeerDisconnected(_) -> todo
      }
    }
    Error(_) -> todo
  }
}

pub type TorrentError {
  PeerError(peer_session.PeerError)
  FileError(simplifile.FileError)
}

fn assign_pieces(
  pieces: List(Piece),
  sessions: List(PeerSession),
) -> List(PeerSession) {
  keep_assigning(pieces, sessions, [])
}

fn keep_assigning(
  pieces: List(Piece),
  sessions: List(PeerSession),
  new_sessions: List(PeerSession),
) -> List(PeerSession) {
  case sessions, pieces {
    [], _ -> new_sessions
    _, [] -> new_sessions
    [session, ..sessions], [piece, ..pieces] -> {
      let new_sessions = [
        PeerSession(..session, piece: Some(new_piece_download(piece))),
        ..sessions
      ]
      keep_assigning(pieces, sessions, new_sessions)
    }
  }
}
