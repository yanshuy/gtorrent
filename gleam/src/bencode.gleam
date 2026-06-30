import gleam/bit_array
import gleam/int
import gleam/json
import gleam/result.{try}
import helpers

pub type Bencode {
  BString(String)
  BInteger(Int)
}

pub type DecodeError {
  UnexpectedEof
  InvalidInteger
  InvalidStringLength
  InvalidUtf8
  InvalidPrefix(Int)
  NoColon
}

pub fn decode(encoded_value: BitArray) -> Result(Bencode, DecodeError) {
  case encoded_value {
    <<":":utf8, rest:bits>> -> {
      case bit_array.to_string(rest) {
        Ok(str) -> Ok(BString(str))
        Error(_) -> Error(InvalidUtf8)
      }
    }

    <<"i":utf8, rest:bits>> -> {
      decode_integer(rest)
      |> result.map(fn(result) {
        let #(integer, _) = result
        integer
      })
    }

    <<_, rest:bits>> -> decode(rest)

    <<>> | <<_:size(1), _rest:bits>> | _ -> Error(NoColon)
  }
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

pub fn to_json(value: Bencode) -> json.Json {
  case value {
    BString(string) -> json.string(string)
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
  }
}
