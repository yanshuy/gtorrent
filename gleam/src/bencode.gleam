import gleam/bit_array
import gleam/io

pub fn decode(encoded_value: BitArray) -> String {
  case encoded_value {
    <<58, rest:bits>> -> {
      case bit_array.to_string(rest) {
        Ok(str) -> str
        Error(_) -> "Invalid data"
      }
    }

    <<_, rest:bits>> -> decode(rest)

    <<>> | <<_:size(1), _rest:bits>> | _ -> {
      io.println("The ':' character is not found in the binary")
      ""
    }
  }
}
