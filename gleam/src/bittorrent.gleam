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
      let res = bit_array.from_string(encode_str) |> bencode.decode
      case res {
        Ok(value) -> bencode.to_json(value) |> json.to_string |> io.println
        Error(err) -> io.println_error(bencode.stringify_error(err))
      }
    }
    [command, ..] -> {
      io.println("Unknown command: " <> command)
      stop(1)
    }
    [] -> {
      io.println("Usage: your_program.sh <command> <args>")
      stop(1)
    }
  }
}

@external(erlang, "init", "stop")
pub fn stop(code: Int) -> Nil
