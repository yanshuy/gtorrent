import gleam/bit_array
import gleam/result.{try}

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
