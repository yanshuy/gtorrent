import argv
import bencode
import gleam/bit_array
import gleam/io
import gleam/json

pub fn main() {
  execute(argv.load().arguments)
}

pub fn execute(args: List(String)) {
  case args {
    ["decode", encode_str, ..] -> {
      let decoded_str = bit_array.from_string(encode_str) |> bencode.decode

      let json_string = json.string(decoded_str) |> json.to_string

      io.println(json_string)
    }
    [command, ..] -> {
      io.println("Unknown command: " <> command)
      panic
    }
    [] -> {
      io.println("Usage: your_program.sh <command> <args>")
      panic
    }
  }
}
