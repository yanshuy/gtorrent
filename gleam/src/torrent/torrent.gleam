import bencode
import gleam/crypto
import gleam/dict
import gleam/int
import gleam/list
import gleam/result.{try}
import gleam/set
import simplifile
import torrent/peer/protocol

pub type TorrentInfo {
  TorrentInfo(
    name: String,
    announce: String,
    length: Int,
    piece_length: Int,
    pieces: List(BitArray),
    info_hash: BitArray,
  )
}

pub fn parse(
  meta_info: bencode.Bencode,
) -> Result(TorrentInfo, bencode.BencodeError) {
  use dict <- try(bencode.dict(meta_info))

  let name = bencode.get_string(dict, "name") |> result.unwrap("Unknown")
  use announce <- try(bencode.get_string(dict, "announce"))

  use info_entries <- try(bencode.get_entries(dict, "info"))
  let info = dict.from_list(info_entries)

  let length = bencode.get_int(info, "length") |> result.unwrap(0)

  use piece_length <- try(bencode.get_int(info, "piece length"))
  use pieces <- try(bencode.get_string_bits(info, "pieces"))

  Ok(TorrentInfo(
    name: name,
    announce: announce,
    length: length,
    piece_length: piece_length,
    pieces: split_piece_hashes(pieces),
    info_hash: info_hash(info_entries),
  ))
}

pub fn info_hash(info_entries: List(#(String, bencode.Bencode))) -> BitArray {
  let bits =
    bencode.BDict(info_entries)
    |> bencode.encode
  crypto.hash(crypto.Sha1, bits)
}

pub fn split_piece_hashes(bits: BitArray) -> List(BitArray) {
  split_piece_hashes_loop(bits, [])
}

fn split_piece_hashes_loop(
  bits: BitArray,
  acc: List(BitArray),
) -> List(BitArray) {
  case bits {
    <<>> -> list.reverse(acc)

    <<hash:bytes-size(20), rest:bits>> ->
      split_piece_hashes_loop(rest, [hash, ..acc])

    _ -> acc
  }
}

pub type PieceInfo {
  PieceInfo(index: Int, hash: BitArray, length: Int)
}

pub type PieceDownload {
  PieceDownload(
    info: PieceInfo,
    blocks: List(BitArray),
    pending_requests: List(BlockRequest),
    outstanding_requests: dict.Dict(Int, BlockRequest),
  )
}

pub type BlockRequest {
  BlockRequest(begin: Int, length: Int)
}

pub type Torrent {
  Torrent(
    info: TorrentInfo,
    download_path: String,
    peers: set.Set(protocol.PeerId),
    pending_pieces: List(PieceInfo),
  )
}

fn new_torrent(
  torrent: TorrentInfo,
  download_path: String,
  peers: List(protocol.PeerId),
) {
  let peers = set.from_list(peers)
  let pieces = new_pieces(torrent.length, torrent.piece_length, torrent.pieces)
  Torrent(
    info: torrent,
    download_path: download_path,
    peers: peers,
    pending_pieces: pieces,
  )
}

// pub fn fetch_torrent(
//   torrent: TorrentInfo,
//   download_path: String,
//   endpoints: List(String),
//   peer_id: BitArray,
// ) -> Result(Nil, TorrentError) {
//   //connect to all endpoints and receive bitfields
//   let sessions =
//     endpoints
//     |> list.take(2)
//     |> list.filter_map(fn(endpoint) {
//       use session <- try(handshake(endpoint, torrent.info_hash, peer_id))
//       receive_bitfield(session)
//     })

//   let #(peers, _bit_fields) =
//     list.fold(sessions, #([], []), fn(acc, session) {
//       let #(peers, bit_fields) = acc
//       let assert Some(bit_field) = session.bit_field
//       #([session.peer_id, ..peers], [bit_field, ..bit_fields])
//     })

//   let torrent = new_torrent(torrent, download_path, peers)

//   download_pieces(torrent, sessions)
//   //assign piece
//   todo
//   // one_piece(session.socket, torrent, session.state, torrent.pieces, 0)
//   // |> result.replace(Nil)
// }

// fn download_pieces(
//   torrent: Torrent,
//   sessions: List(PeerSession),
// ) -> Result(Torrent, TorrentError) {
//   let sessions = assign_pieces(torrent.pending_pieces, sessions)
//   // there may be a situation where sessions are more than pending pieces: endgame?
//   let writer =
//     file_io.new_file_writer(torrent.download_path, torrent.info.length)

//   list.try_each(sessions, fn(session) { handle_peer_event(torrent, sessions) })
// }

// fn handle_peer_event(
//   torrent: Torrent,
//   session: PeerSession,
// ) -> Result(Torrent, TorrentError) {
//   use event <- try(peer_exchange(session) |> map_error(ProtocolError))
//   case event {
//     SessionUpdate(session) -> handle_peer_event(torrent, session)
//     PieceDownloaded(index, data, session) -> {
//       let offset = index * torrent.info.piece_length
//       case download_piece(torrent.download_path, data, offset) {
//         Ok(Nil) -> {
//           let set = set.insert(torrent.downloaded_pieces, index)
//           let new_torrent = Torrent(..torrent, downloaded_pieces: set)
//           handle_peer_event(new_torrent, session)
//         }
//         Error(err) -> Error(FileError(err))
//       }
//     }
//   }
// }

fn download_piece(
  download_path,
  data,
  offset,
) -> Result(Nil, simplifile.FileError) {
  todo
}

pub const block_size = 16_384

pub fn new_pieces(
  file_length: Int,
  piece_length: Int,
  piece_hashes: List(BitArray),
) -> List(PieceInfo) {
  new_pieces_loop(piece_hashes, 0, file_length, piece_length, [])
}

fn new_pieces_loop(
  hashes: List(BitArray),
  index: Int,
  file_length: Int,
  piece_length: Int,
  acc: List(PieceInfo),
) -> List(PieceInfo) {
  case hashes {
    [] -> list.reverse(acc)

    [last_hash] -> {
      let length = case file_length % piece_length {
        0 -> piece_length
        rem -> rem
      }
      let piece = PieceInfo(index: index, hash: last_hash, length: length)
      list.reverse([piece, ..acc])
    }

    [head_hash, ..tail_hashes] -> {
      let piece = PieceInfo(index: index, hash: head_hash, length: piece_length)
      new_pieces_loop(tail_hashes, index + 1, file_length, piece_length, [
        piece,
        ..acc
      ])
    }
  }
}

pub fn piece_block_requests(piece_length: Int) -> List(BlockRequest) {
  let block_count = { piece_length + block_size - 1 } / block_size
  piece_block_requests_loop(piece_length, block_count - 1, [])
}

fn piece_block_requests_loop(
  length: Int,
  block: Int,
  requests: List(BlockRequest),
) -> List(BlockRequest) {
  case block < 0 {
    False -> {
      let begin = block * block_size
      let block_length = int.min(block_size, length - begin)
      let request = BlockRequest(begin: begin, length: block_length)
      piece_block_requests_loop(length, block - 1, [request, ..requests])
    }
    True -> requests
  }
}

pub fn piece_size(index: Int, file_length: Int, piece_length: Int) -> Int {
  let piece_count = { file_length + piece_length - 1 } / piece_length
  case piece_count - 1 == index {
    True ->
      case file_length % piece_length {
        0 -> piece_length
        rem -> rem
      }
    False -> piece_length
  }
}

pub fn new_piece_download(piece: PieceInfo) {
  PieceDownload(
    info: piece,
    blocks: [],
    pending_requests: piece_block_requests(piece.length),
    outstanding_requests: dict.new(),
  )
}
