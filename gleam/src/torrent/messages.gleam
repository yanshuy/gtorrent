import gleam/erlang/process
import torrent/peer/protocol
import torrent/torrent

pub type PeerEvent {
  Ready(peer: protocol.PeerId, subject: process.Subject(torrent.PieceInfo))
  LeasePiece(peer_id: protocol.PeerId, bitfield: BitArray)
  ReturnPieceLease(peer_id: protocol.PeerId, piece_index: Int)
  PieceCompleted(peer: protocol.PeerId, index: Int, piece: BitArray)
  PeerDisconnected(peer: protocol.PeerId, reason: String)
}
