import gleam/bit_array
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
  InvalidDictionaryKey
  InvalidUtf8
  NoColon
  InvalidPrefix(Int)
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
  let assert Ok(num_str) = bit_array.to_string(bits)
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
      use #(string, rest) <- try(
        decode_string(bits) |> result.replace_error(InvalidDictionaryKey),
      )
      let assert BString(key_bits) = string
      let assert Ok(key) = bit_array.to_string(key_bits)

      use #(value, rest) <- try(decode_loop(rest))

      decode_dictionary(rest, [#(key, value), ..entries])
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

pub fn stringify_error(error: DecodeError) -> String {
  case error {
    UnexpectedEof -> "Unexpected end of input"
    InvalidInteger -> "Invalid integer"
    InvalidStringLength -> "Invalid string length"
    InvalidUtf8 -> "Invalid UTF-8"
    InvalidPrefix(byte) -> "Invalid prefix: " <> int.to_string(byte)
    NoColon -> "The ':' character is not found in the binary"
    InvalidDictionaryKey -> "Invalid dict key"
  }
}
