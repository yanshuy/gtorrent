import gleam/erlang/process
import gleam/option.{None, Some}
import torrent/peer/protocol
import torrent/torrent

pub type PeerEvent {
  Ready(
    peer: protocol.PeerId,
    bitfield: BitArray,
    reply_subject: process.Subject(torrent.PieceInfo),
  )
  LeasePiece(
    peer_id: protocol.PeerId,
    reply_subject: process.Subject(torrent.PieceInfo),
  )
  PieceCompleted(index: Int, data: BitArray)
  PeerDisconnected(peer: protocol.PeerId, reason: String)
}
