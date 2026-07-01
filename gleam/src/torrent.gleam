import bencode
import gleam/bit_array
import gleam/dict
import gleam/int
import gleam/io
import gleam/result.{try}

pub fn print_info(meta_info: bencode.Bencode) -> Result(Nil, TorrentError) {
  case meta_info {
    bencode.BDict(entries) -> {
      let dict = dict.from_list(entries)
      use tracker <- try(get_string(dict, "announce"))
      use info <- try(get_dict(dict, "info"))
      use length <- try(get_int(info, "length"))

      io.println("Tracker URL: " <> tracker)
      io.println("Length: " <> int.to_string(length))
      Ok(Nil)
    }
    _ -> Error(InvalidTorrent("Not a valid torrent"))
  }
}

pub type TorrentError {
  InvalidTorrent(String)
}

pub fn describe_error(error: TorrentError) -> String {
  case error {
    InvalidTorrent(message) -> message
  }
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

fn get_dict(
  torrent: dict.Dict(String, bencode.Bencode),
  key: String,
) -> Result(dict.Dict(String, bencode.Bencode), TorrentError) {
  use value <- try(get_value(torrent, key))

  case value {
    bencode.BDict(entries) -> Ok(dict.from_list(entries))
    _ -> Error(InvalidTorrent("Expected dictionary for key: " <> key))
  }
}
