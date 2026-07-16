import gleam/erlang/process
import torrent/peer/protocol
import torrent/torrent

pub type PeerEvent {
  Ready(peer: protocol.PeerId, bitfield: BitArray)
  LeasePiece(
    peer_id: protocol.PeerId,
    reply_subject: process.Subject(torrent.PieceInfo),
  )
  PieceCompleted(index: Int, piece: BitArray)
  PeerDisconnected(peer: protocol.PeerId, reason: String)
}
