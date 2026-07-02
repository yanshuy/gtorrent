import argv
import bencode
import gleam/bit_array
import gleam/io
import gleam/json
import gleam/result.{map_error, try}
import gleam/string
import simplifile
import torrent
import tracker

pub fn main() {
  execute(argv.load().arguments)
}

pub fn execute(args: List(String)) {
  case execute_cmd(args) {
    Ok(_) -> Nil
    Error(err) -> {
      io.println_error(describe_cmd_error(err))
      stop(1)
    }
  }
}

pub fn execute_cmd(args: List(String)) -> Result(Nil, CmdError) {
  case args {
    ["decode", encode_str, ..] -> cmd_decode(encode_str)

    ["info", filename, ..] -> cmd_info(filename)

    ["peers", filename] -> cmd_peers(filename)

    [command, ..] -> Error(UnknownCommand(command))

    [] -> Error(InvalidArguments)
  }
}

pub type CmdError {
  UnknownCommand(String)
  InvalidArguments
  AppStartError(StartError)
  FileError(simplifile.FileError)
  DecodeError(bencode.DecodeError)
  TorrentError(torrent.TorrentError)
  TrackerError(tracker.TrackerError)
}

fn cmd_decode(encode_str: String) -> Result(Nil, CmdError) {
  use value <- try(
    bit_array.from_string(encode_str)
    |> bencode.decode
    |> map_error(DecodeError),
  )
  let json_str = bencode.to_json(value) |> json.to_string
  io.println(json_str)
  Ok(Nil)
}

fn cmd_info(filename: String) -> Result(Nil, CmdError) {
  use bits <- try(simplifile.read_bits(filename) |> map_error(FileError))
  use data <- try(bencode.decode(bits) |> map_error(DecodeError))

  use _ <- try(torrent.print_info(data) |> map_error(TorrentError))
  Ok(Nil)
}

fn cmd_peers(filename: String) -> Result(Nil, CmdError) {
  use _ <- try(application_start(Inets) |> map_error(AppStartError))

  use bits <- try(simplifile.read_bits(filename) |> map_error(FileError))
  use data <- try(bencode.decode(bits) |> map_error(DecodeError))

  use peers <- try(tracker.get_peers(data) |> map_error(TrackerError))

  io.println(string.join(peers, with: "\n"))
  Ok(Nil)
}

fn describe_cmd_error(error: CmdError) {
  case error {
    UnknownCommand(command) -> "Unknown command: " <> command
    InvalidArguments -> "Usage: your_program.sh <command> <args>"
    AppStartError(StartError(reason)) -> reason
    FileError(err) -> simplifile.describe_error(err)
    DecodeError(err) -> bencode.describe_error(err)
    TorrentError(err) -> torrent.describe_error(err)
    TrackerError(err) -> tracker.describe_error(err)
  }
}

@external(erlang, "init", "stop")
pub fn stop(code: Int) -> Nil

@external(erlang, "ffi/bittorrent_ffi", "start")
fn application_start(app: Application) -> Result(Nil, StartError)

pub type Application {
  Inets
}

pub type StartError {
  StartError(reason: String)
}
