import bencode
import gleam/bit_array
import gleam/list
import gleam/result.{replace_error, try}
import mug
import torrent/peer/protocol.{Handshake, MetadataRequest}

// import torrent/peer/protocol

const message_id = 20

pub fn send_handshake(
  socket: mug.Socket,
) -> Result(Nil, protocol.ProtocolError) {
  let extensions = [#("ut_metadata", 10)]
  let ext_message = Handshake(extensions: extensions)

  let encoded = encode_extension_message(ext_message)

  let message_len = 1 + 1 + bit_array.byte_size(encoded)
  let extension_message = <<
    message_len:big-size(32),
    message_id:int,
    0:int,
    encoded:bits,
  >>
  protocol.send_message(socket, extension_message)
}

pub fn send_metadata_request(socket: mug.Socket, extension_id: Int) {
  let ext_message = MetadataRequest(0)
  let encoded = encode_extension_message(ext_message)

  let message_len = 1 + 1 + bit_array.byte_size(encoded)
  let message = <<
    message_len:big-size(32),
    message_id:int,
    extension_id:int,
    encoded:bits,
  >>
  protocol.send_message(socket, message)
}

fn encode_extension_message(message: protocol.ExtensionMessage) {
  case message {
    Handshake(extensions) -> {
      let extensions =
        extensions
        |> list.map(fn(item) { #(item.0, bencode.Int(item.1)) })
        |> bencode.Dict
      [
        #("m", extensions),
      ]
      |> bencode.Dict
      |> bencode.to_bencode
      |> bencode.encode
    }
    MetadataRequest(piece_index) -> {
      [#("msg_type", bencode.Int(0)), #("piece", bencode.Int(piece_index))]
      |> bencode.Dict
      |> bencode.to_bencode
      |> bencode.encode
    }
  }
}
