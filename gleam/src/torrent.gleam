import bencode
import gleam/bit_array
import gleam/dict
import gleam/int
import gleam/io
import gleam/result.{try}
import gleam/string

pub fn print_info(meta_info: bencode.Bencode) -> Result(Nil, TorrentError) {
  case meta_info {
    bencode.BDict(entries) -> {
      let dict = dict.from_list(entries)
      use tracker <- try(get_string(dict, "announce"))
      use info_entries <- try(get_entries(dict, "info"))
      let info_dict = dict.from_list(info_entries)
      use length <- try(get_int(info_dict, "length"))

      let encoded =
        digest(info_entries) |> bit_array.base16_encode |> string.lowercase

      io.println("Tracker URL: " <> tracker)
      io.println("Length: " <> int.to_string(length))
      io.println("Info Hash: " <> encoded)
      Ok(Nil)
    }
    _ -> Error(InvalidTorrent("Not a valid torrent"))
  }
}

fn digest(info_entries: List(#(String, bencode.Bencode))) {
  let bits = bencode.BDict(info_entries) |> bencode.encode
  hash(Sha, bits)
}

pub type TorrentError {
  InvalidTorrent(String)
}

fn get_value(
  torrent: dict.Dict(String, bencode.Bencode),
  key: String,
) -> Result(bencode.Bencode, TorrentError) {
  dict.get(torrent, key)
  |> result.replace_error(InvalidTorrent("Missing key: " <> key))
}

fn get_string(
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

fn get_int(
  torrent: dict.Dict(String, bencode.Bencode),
  key: String,
) -> Result(Int, TorrentError) {
  use value <- try(get_value(torrent, key))

  case value {
    bencode.BInteger(integer) -> Ok(integer)
    _ -> Error(InvalidTorrent("Expected integer for key: " <> key))
  }
}

fn get_entries(
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
    InvalidTorrent(message) -> message
  }
}

@external(erlang, "crypto", "hash")
fn hash(algorithm: Algorithm, data: BitArray) -> BitArray

type Algorithm {
  Sha
}
