import gleam/bit_array
import gleam/crypto
import gleam/dict
import gleam/int
import gleam/json
import gleam/list
import gleam/result.{try}
import helpers

pub type Bencode {
  BDict(List(#(String, Bencode)))
  BList(List(Bencode))
  BString(BitArray)
  BInteger(Int)
}

pub type DecodeError {
  UnexpectedEof
  InvalidInteger
  InvalidStringLength
  InvalidUtf8
  InvalidPrefix(Int)
  MissingKey(String)
  InvalidTorrent(String)
  NoColon
}

pub fn decode(encoded_value: BitArray) -> Result(Bencode, DecodeError) {
  use #(value, _) <- try(decode_loop(encoded_value))
  Ok(value)
}

fn decode_loop(bits: BitArray) -> Result(#(Bencode, BitArray), DecodeError) {
  case bits {
    <<"i":utf8, rest:bits>> -> decode_integer(rest)

    <<"l":utf8, rest:bits>> -> decode_list(rest, [])

    <<"d":utf8, rest:bits>> -> decode_dictionary(rest, [])

    <<byte, _:bits>> if byte >= 48 && byte <= 57 -> decode_string(bits)

    <<_:size(1), _rest:bits>> -> Error(InvalidUtf8)
    <<>> | _ -> Error(UnexpectedEof)
  }
}

fn decode_string(bits: BitArray) -> Result(#(Bencode, BitArray), DecodeError) {
  use #(bits, rest) <- try(
    helpers.take_until(bits, ":")
    |> result.replace_error(NoColon),
  )
  use num_str <- try(
    bit_array.to_string(bits)
    |> result.replace_error(InvalidUtf8),
  )

  use str_length <- try(
    int.parse(num_str) |> result.replace_error(InvalidStringLength),
  )

  use string_bits <- try(
    bit_array.slice(rest, 0, str_length)
    |> result.replace_error(UnexpectedEof),
  )

  let end = bit_array.byte_size(rest) - str_length
  use rem <- try(
    bit_array.slice(rest, str_length, end)
    |> result.replace_error(UnexpectedEof),
  )

  Ok(#(BString(string_bits), rem))
}

fn decode_integer(bits: BitArray) -> Result(#(Bencode, BitArray), DecodeError) {
  use #(bits, rest) <- try(
    helpers.take_until(bits, "e")
    |> result.replace_error(InvalidInteger),
  )

  let assert Ok(str) = bit_array.to_string(bits)

  use integer <- try(int.parse(str) |> result.replace_error(InvalidInteger))

  Ok(#(BInteger(integer), rest))
}

fn decode_list(
  bits: BitArray,
  list: List(Bencode),
) -> Result(#(Bencode, BitArray), DecodeError) {
  case bits {
    <<"e":utf8, rest:bits>> -> {
      let blist = BList(list.reverse(list))
      Ok(#(blist, rest))
    }
    _ -> {
      use #(decoded, rest) <- try(decode_loop(bits))
      decode_list(rest, [decoded, ..list])
    }
  }
}

fn decode_dictionary(
  bits: BitArray,
  entries: List(#(String, Bencode)),
) -> Result(#(Bencode, BitArray), DecodeError) {
  case bits {
    <<"e":utf8, rest:bits>> -> {
      let bdict = BDict(list.reverse(entries))
      Ok(#(bdict, rest))
    }

    _ -> {
      use #(string, rest) <- try(decode_string(bits))
      let assert BString(key_bits) = string
      let assert Ok(key) = bit_array.to_string(key_bits)

      use #(value, rest) <- try(decode_loop(rest))

      decode_dictionary(rest, [#(key, value), ..entries])
    }
  }
}

pub fn encode(value: Bencode) -> BitArray {
  case value {
    BInteger(integer) -> <<"i":utf8, int.to_string(integer):utf8, "e":utf8>>

    BString(bits) -> {
      let length = bit_array.byte_size(bits) |> int.to_string
      <<length:utf8, ":":utf8, bits:bits>>
    }

    BList(values) -> {
      let list = encode_list(values, [])
      <<"l":utf8, list:bits, "e":utf8>>
    }

    BDict(entries) -> {
      let entries = encode_entries(entries, [])
      <<"d":utf8, entries:bits, "e":utf8>>
    }
  }
}

fn encode_list(values: List(Bencode), acc: List(BitArray)) -> BitArray {
  case values {
    [] ->
      list.reverse(acc)
      |> bit_array.concat

    [head, ..rest] -> {
      let first = encode(head)
      encode_list(rest, [first, ..acc])
    }
  }
}

fn encode_entries(
  entries: List(#(String, Bencode)),
  acc: List(BitArray),
) -> BitArray {
  case entries {
    [] ->
      list.reverse(acc)
      |> bit_array.concat

    [#(key, value), ..rest] -> {
      let key = encode(BString(bit_array.from_string(key)))
      let value = encode(value)
      encode_entries(rest, [<<key:bits, value:bits>>, ..acc])
    }
  }
}

pub fn to_json(value: Bencode) -> json.Json {
  case value {
    BDict(entries) ->
      json.object(list.map(entries, fn(entry) { #(entry.0, to_json(entry.1)) }))
    BList(list) -> json.array(list, to_json)
    BString(bits) -> {
      let assert Ok(string) = bit_array.to_string(bits)
      json.string(string)
    }
    BInteger(integer) -> json.int(integer)
  }
}

pub type Torrent {
  Torrent(
    name: String,
    announce: String,
    length: Int,
    piece_length: Int,
    pieces: List(BitArray),
    info_hash: BitArray,
  )
}

pub fn parse_torrent(torrent: Bencode) -> Result(Torrent, DecodeError) {
  use dict <- try(dict(torrent))
  let name = get_string(dict, "name") |> result.unwrap("Unknown")
  use tracker <- try(get_string(dict, "announce"))

  use info_entries <- try(get_entries(dict, "info"))
  let info_dict = dict.from_list(info_entries)

  // use length <- try(get_int(info_dict, "length"))
  let length = get_int(info_dict, "length") |> result.unwrap(0)

  use piece_length <- try(get_int(info_dict, "piece length"))
  use pieces <- try(get_string_bits(info_dict, "pieces"))

  let piece_hashes = split_piece_hashes(pieces, [])

  Ok(Torrent(
    name: name,
    announce: tracker,
    length: length,
    piece_length: piece_length,
    pieces: piece_hashes,
    info_hash: digest_entries(info_entries),
  ))
}

pub fn dict(
  meta_info: Bencode,
) -> Result(dict.Dict(String, Bencode), DecodeError) {
  case meta_info {
    BDict(entries) -> {
      let dict = dict.from_list(entries)
      Ok(dict)
    }
    _ -> Error(InvalidTorrent("Not valid"))
  }
}

pub fn digest_entries(info_entries: List(#(String, Bencode))) {
  let bits = BDict(info_entries) |> encode
  crypto.hash(crypto.Sha1, bits)
}

pub fn split_piece_hashes(
  bits: BitArray,
  acc: List(BitArray),
) -> List(BitArray) {
  case bits {
    <<>> -> list.reverse(acc)

    <<first:bytes-size(20), rest:bits>> ->
      split_piece_hashes(rest, [first, ..acc])

    _ -> acc
  }
}

pub fn get_value(
  torrent: dict.Dict(String, Bencode),
  key: String,
) -> Result(Bencode, DecodeError) {
  dict.get(torrent, key)
  |> result.replace_error(MissingKey(key))
}

pub fn get_string(
  torrent: dict.Dict(String, Bencode),
  key: String,
) -> Result(String, DecodeError) {
  use value <- try(get_value(torrent, key))

  let error = InvalidTorrent("Expected utf8 string for key: " <> key)

  case value {
    BString(bits) -> bit_array.to_string(bits) |> result.replace_error(error)

    _ -> Error(error)
  }
}

pub fn get_string_bits(
  torrent: dict.Dict(String, Bencode),
  key: String,
) -> Result(BitArray, DecodeError) {
  use value <- try(get_value(torrent, key))

  let error = InvalidTorrent("Expected string for key: " <> key)
  case value {
    BString(bits) -> Ok(bits)
    _ -> Error(error)
  }
}

pub fn get_int(
  torrent: dict.Dict(String, Bencode),
  key: String,
) -> Result(Int, DecodeError) {
  use value <- try(get_value(torrent, key))

  case value {
    BInteger(integer) -> Ok(integer)
    _ -> Error(InvalidTorrent("Expected integer for key: " <> key))
  }
}

pub fn get_entries(
  torrent: dict.Dict(String, Bencode),
  key: String,
) -> Result(List(#(String, Bencode)), DecodeError) {
  use value <- try(get_value(torrent, key))

  case value {
    BDict(entries) -> Ok(entries)
    _ -> Error(InvalidTorrent("Expected dictionary for key: " <> key))
  }
}

pub fn describe_error(error: DecodeError) -> String {
  case error {
    UnexpectedEof -> "Unexpected end of input"
    InvalidInteger -> "Invalid integer"
    InvalidStringLength -> "Invalid string length"
    InvalidUtf8 -> "Invalid UTF-8"
    InvalidPrefix(byte) -> "Invalid prefix: " <> int.to_string(byte)
    NoColon -> "The ':' character is not found in the binary"
    MissingKey(key) -> "Missing Key: " <> key
    InvalidTorrent(err) -> err
  }
}
