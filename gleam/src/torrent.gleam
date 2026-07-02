import bencode
import gleam/bit_array
import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/result.{try}
import gleam/string

pub fn print_info(meta_info: bencode.Bencode) -> Result(Nil, TorrentError) {
  use dict <- try(dict(meta_info))

  use tracker <- try(get_string(dict, "announce"))
  io.println("Tracker URL: " <> tracker)

  use info_entries <- try(get_entries(dict, "info"))
  let info_dict = dict.from_list(info_entries)

  use length <- try(get_int(info_dict, "length"))
  io.println("Length: " <> int.to_string(length))

  let encoded =
    digest_entries(info_entries)
    |> bit_array.base16_encode
    |> string.lowercase
  io.println("Info Hash: " <> encoded)

  use piece_length <- try(get_int(info_dict, "piece length"))
  io.println("Piece Length: " <> int.to_string(piece_length))

  use pieces <- try(get_value(info_dict, "pieces"))
  let assert bencode.BString(bits) = pieces
  let hashes = encode_piece_hashes(bits, []) |> string.join(with: "\n")
  io.println("Piece Hashes: \n" <> hashes)

  Ok(Nil)
}

pub fn dict(
  meta_info: bencode.Bencode,
) -> Result(dict.Dict(String, bencode.Bencode), TorrentError) {
  case meta_info {
    bencode.BDict(entries) -> {
      let dict = dict.from_list(entries)
      Ok(dict)
    }
    _ -> Error(InvalidTorrent("Not valid"))
  }
}

pub fn digest_entries(info_entries: List(#(String, bencode.Bencode))) {
  let bits = bencode.BDict(info_entries) |> bencode.encode
  hash(Sha, bits)
}

fn encode_piece_hashes(bits: BitArray, acc: List(String)) -> List(String) {
  case bits {
    <<>> -> list.reverse(acc)

    <<first:bytes-size(20), rest:bits>> -> {
      let encoded = bit_array.base16_encode(first) |> string.lowercase
      encode_piece_hashes(rest, [encoded, ..acc])
    }

    _ -> acc
  }
}

pub type TorrentError {
  MissingKey(String)
  InvalidTorrent(String)
}

pub fn get_value(
  torrent: dict.Dict(String, bencode.Bencode),
  key: String,
) -> Result(bencode.Bencode, TorrentError) {
  dict.get(torrent, key)
  |> result.replace_error(MissingKey(key))
}

pub fn get_string(
  torrent: dict.Dict(String, bencode.Bencode),
  key: String,
) -> Result(String, TorrentError) {
  use value <- try(get_value(torrent, key))

  let error = InvalidTorrent("Expected string for key: " <> key)

  case value {
    bencode.BString(bits) ->
      bit_array.to_string(bits) |> result.replace_error(error)

    _ -> Error(error)
  }
}

pub fn get_string_bits(
  torrent: dict.Dict(String, bencode.Bencode),
  key: String,
) -> Result(BitArray, TorrentError) {
  use value <- try(get_value(torrent, key))

  let error = InvalidTorrent("Expected string for key: " <> key)
  case value {
    bencode.BString(bits) -> Ok(bits)
    _ -> Error(error)
  }
}

pub fn get_int(
  torrent: dict.Dict(String, bencode.Bencode),
  key: String,
) -> Result(Int, TorrentError) {
  use value <- try(get_value(torrent, key))

  case value {
    bencode.BInteger(integer) -> Ok(integer)
    _ -> Error(InvalidTorrent("Expected integer for key: " <> key))
  }
}

pub fn get_entries(
  torrent: dict.Dict(String, bencode.Bencode),
  key: String,
) -> Result(List(#(String, bencode.Bencode)), TorrentError) {
  use value <- try(get_value(torrent, key))

  case value {
    bencode.BDict(entries) -> Ok(entries)
    _ -> Error(InvalidTorrent("Expected dictionary for key: " <> key))
  }
}

pub fn describe_error(error: TorrentError) -> String {
  case error {
    MissingKey(key) -> "Missing key: " <> key
    InvalidTorrent(message) -> message
  }
}

@external(erlang, "crypto", "hash")
pub fn hash(algorithm: Algorithm, data: BitArray) -> BitArray

pub type Algorithm {
  Sha
}
