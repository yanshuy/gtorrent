import gleam/bit_array
import gleam/list
import gleam/result.{try}
import gleam/string

pub fn take_until(
  bits: BitArray,
  delimiter: String,
) -> Result(#(BitArray, BitArray), Nil) {
  case bit_array.from_string(delimiter) {
    <<delim:int, _:bits>> if delim < 128 -> take_until_byte(bits, delim)
    _ -> Error(Nil)
  }
}

pub fn take_until_byte(
  bits: BitArray,
  delimiter: Int,
) -> Result(#(BitArray, BitArray), Nil) {
  use index <- try(find_byte_index(bits, delimiter))

  let assert Ok(before) = bit_array.slice(bits, at: 0, take: index)
  let end = bit_array.byte_size(bits) - index - 1
  let assert Ok(after) = bit_array.slice(bits, at: index + 1, take: end)
  Ok(#(before, after))
}

pub fn find_byte_index(bits: BitArray, target: Int) -> Result(Int, Nil) {
  find_byte_index_loop(bits, target, 0)
}

pub fn find_byte_index_loop(
  bits: BitArray,
  target: Int,
  idx: Int,
) -> Result(Int, Nil) {
  case bits {
    <<byte, rest:bits>> -> {
      case byte == target {
        True -> Ok(idx)
        False -> find_byte_index_loop(rest, target, idx + 1)
      }
    }
    <<>> | <<_:size(1), _:bits>> | _ -> Error(Nil)
  }
}

// ai written
pub fn percent_encode(bits: BitArray) -> String {
  percent_encode_loop(bits, [])
}

fn percent_encode_loop(bits: BitArray, acc: List(String)) -> String {
  case bits {
    <<>> -> list.reverse(acc) |> string.concat

    <<byte, rest:bits>> -> {
      let part = case is_unreserved(byte) {
        True -> ascii(byte)
        False -> "%" <> bit_array.base16_encode(<<byte:size(8)>>)
      }

      percent_encode_loop(rest, [part, ..acc])
    }

    _ -> panic
  }
}

fn is_unreserved(byte: Int) -> Bool {
  case byte {
    _ if byte >= 65 && byte <= 90 -> True
    _ if byte >= 97 && byte <= 122 -> True
    _ if byte >= 48 && byte <= 57 -> True
    45 | 46 | 95 | 126 -> True
    _ -> False
  }
}

fn ascii(byte: Int) -> String {
  let assert Ok(string) = <<byte>> |> bit_array.to_string
  string
}
