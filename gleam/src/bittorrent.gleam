import argv
import bencode
import gleam/bit_array
import gleam/io
import gleam/json
import gleam/result.{try}
import simplifile
import torrent

pub fn main() {
  case execute(argv.load().arguments) {
    Ok(_) -> Nil
    Error(err) -> {
      io.print_error(describe_cmd_error(err))
      stop(1)
    }
  }
}

pub fn execute(args: List(String)) -> Result(Nil, CmdError) {
  case args {
    ["decode", encode_str, ..] -> cmd_decode(encode_str)

    ["info", filename, ..] -> cmd_info(filename)

    [command, ..] -> Error(UnknownCommand(command))

    [] -> Error(InvalidArguments)
  }
}

pub type CmdError {
  UnknownCommand(String)
  InvalidArguments
  FileError(simplifile.FileError)
  DecodeError(bencode.DecodeError)
  TorrentError(torrent.TorrentError)
}

fn cmd_decode(encode_str: String) -> Result(Nil, CmdError) {
  use value <- try(
    bit_array.from_string(encode_str)
    |> bencode.decode
    |> result.map_error(DecodeError),
  )
  let json_str = bencode.to_json(value) |> json.to_string
  io.println(json_str)
  Ok(Nil)
}

fn cmd_info(filename: String) -> Result(Nil, CmdError) {
  use bits <- try(simplifile.read_bits(filename) |> result.map_error(FileError))
  use data <- try(bencode.decode(bits) |> result.map_error(DecodeError))

  use _ <- try(torrent.print_info(data) |> result.map_error(TorrentError))
  Ok(Nil)
}

fn describe_cmd_error(error: CmdError) {
  case error {
    UnknownCommand(command) -> "Unknown command: " <> command
    InvalidArguments -> "Usage: your_program.sh <command> <args>"
    FileError(err) -> simplifile.describe_error(err)
    DecodeError(err) -> bencode.stringify_error(err)
    TorrentError(err) -> torrent.describe_error(err)
  }
}

@external(erlang, "init", "stop")
pub fn stop(code: Int) -> Nil
