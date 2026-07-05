import gleam/bit_array
import gleam/erlang/process
import torrent/peer/protocol
import torrent/torrent

pub type WorkerCmd {
  AssignPiece(torrent.PieceInfo)
  Stop
}

pub type PeerEvent {
  Ready(
    peer: protocol.PeerId,
    worker: process.Subject(WorkerCmd),
    bitfield: BitArray,
  )

  PieceCompleted(peer: protocol.PeerId, index: Int, data: BitArray)

  PeerDisconnected(protocol.PeerId)
}
