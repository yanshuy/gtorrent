import bencode
import gleam/bit_array
import gleam/crypto
import gleam/dict
import gleam/list
import gleam/pair
import gleam/result.{replace_error, try}
import gleam/string
import gleam/uri

pub type TorrentInfo {
  TorrentInfo(
    name: String,
    length: Int,
    piece_length: Int,
    pieces: List(BitArray),
    info_hash: BitArray,
  )
}

pub fn parse(
  meta_info: bencode.Bencode,
) -> Result(#(String, TorrentInfo), bencode.BencodeError) {
  use dict <- try(
    bencode.dict(meta_info)
    |> replace_error(bencode.InvalidTorrent("expected meta info to be a dict")),
  )

  let name = bencode.get_string(dict, "name") |> result.unwrap("Unknown")
  use announce <- try(bencode.get_string(dict, "announce"))

  use info_entries <- try(bencode.get_entries(dict, "info"))
  let info = dict.from_list(info_entries)

  let length = bencode.get_int(info, "length") |> result.unwrap(0)

  use piece_length <- try(bencode.get_int(info, "piece length"))
  use pieces <- try(bencode.get_string_bits(info, "pieces"))

  #(
    announce,
    TorrentInfo(
      name: name,
      length: length,
      piece_length: piece_length,
      pieces: split_piece_hashes(pieces),
      info_hash: info_hash(info_entries),
    ),
  )
  |> Ok
}

pub fn from_metadata(metadata: bencode.Bencode, info_hash: BitArray) {
  use dict <- try(
    bencode.dict(metadata)
    |> replace_error(bencode.InvalidTorrent("expected meta info to be a dict")),
  )

  let name = bencode.get_string(dict, "name") |> result.unwrap("Unknown")
  use length <- try(bencode.get_int(dict, "length"))

  use piece_length <- try(bencode.get_int(dict, "piece length"))
  use pieces <- try(bencode.get_string_bits(dict, "pieces"))

  TorrentInfo(
    name: name,
    length: length,
    piece_length: piece_length,
    pieces: split_piece_hashes(pieces),
    info_hash: info_hash,
  )
  |> Ok
}

pub fn parse_magnet(
  magnet_link: String,
) -> Result(#(String, BitArray), String) {
  use #(_, query_param) <- try(
    string.split_once(magnet_link, "?")
    |> replace_error("invalid magnet link"),
  )

  use dict <- try(
    query_param
    |> string.split("&")
    |> list.try_map(string.split_once(_, "="))
    |> replace_error("invalid magnet link")
    |> result.map(dict.from_list),
  )

  use tr <- try(
    dict.get(dict, "tr") |> replace_error("'tr' (Tracker URL) is missing"),
  )
  use announce <- try(
    uri.percent_decode(tr) |> replace_error("invalid 'tr' (Tracker URL)"),
  )

  use xt <- try(
    dict.get(dict, "xt") |> replace_error("'xt' (Info Hash) is missing"),
  )
  use info_hash <- try(
    string.split_once(xt, "urn:btih:")
    |> result.map(pair.second)
    |> result.try(bit_array.base16_decode)
    |> replace_error("invalid 'xt' (Info Hash)"),
  )

  #(announce, info_hash) |> Ok
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

pub type Piece {
  Piece(PieceInfo)
  PieceIndex(Int)
}

pub type PieceInfo {
  PieceInfo(index: Int, hash: BitArray, length: Int)
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

    [hash] -> {
      let length = case file_length % piece_length {
        0 -> piece_length
        rem -> rem
      }
      let piece = PieceInfo(index: index, hash: hash, length: length)
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
