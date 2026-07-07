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

pub const block_size = 16_384

pub fn new_pieces(
  file_length: Int,
  piece_length: Int,
  piece_hashes: List(BitArray),
) -> List(PieceInfo) {
  new_pieces_loop(piece_hashes, file_length, piece_length, 0, [])
}

fn new_pieces_loop(
  hashes: List(BitArray),
  file_length: Int,
  piece_length: Int,
  index: Int,
  acc: List(PieceInfo),
) -> List(PieceInfo) {
  case hashes {
    [] -> acc

    [last_hash] -> {
      let length = case file_length % piece_length {
        0 -> piece_length
        rem -> rem
      }
      let piece = PieceInfo(index: index, hash: last_hash, length: length)
      list.reverse([piece, ..acc])
    }

    [hash, ..rest] -> {
      let piece = PieceInfo(index: index, hash: hash, length: piece_length)
      new_pieces_loop(rest, file_length, piece_length, index + 1, [piece, ..acc])
    }
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
