import bencode
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/result.{map_error, replace_error, try}
import mug.{ConnectionOptions}

pub type PeerMessage {
  Choke
  Unchoke
  Interested
  NotInterested
  Have
  BitField(BitArray)
  Request(piece_index: Int, begin: Int, length: Int)
  Piece(piece_index: Int, begin: Int, block: BitArray)
  Extension(message: ExtensionMessage)
}

pub type ExtensionMessage {
  Handshake(extensions: List(#(String, Int)))
}

pub type PeerId {
  PeerId(BitArray)
}

const message_timeout = 5000

pub type Endpoint {
  Endpoint(ip4: String, port: Int)
}

pub fn connect(endpoint: Endpoint) -> Result(mug.Socket, ProtocolError) {
  mug.connect(ConnectionOptions(
    host: endpoint.ip4,
    port: endpoint.port,
    timeout: message_timeout,
    ip_version_preference: mug.Ipv4Only,
  ))
  |> map_error(fn(err) {
    case err {
      mug.ConnectFailedIpv4(err) -> TCPError(err)
      _ -> panic
    }
  })
}

pub fn handshake(endpoint: Endpoint, info_hash: BitArray, peer_id: PeerId) {
  use socket <- try(connect(endpoint))
  let PeerId(id) = peer_id
  use #(peer_peer_id, reserved) <- try(peer_handshake(socket, info_hash, id))

  case reserved {
    <<_:size(64 - 20), 1:size(1), _:bits>> -> #(socket, peer_peer_id, True)
    _ -> #(socket, peer_peer_id, False)
  }
  |> Ok
}

fn peer_handshake(
  socket: mug.Socket,
  info_hash: BitArray,
  peer_id: BitArray,
) -> Result(#(PeerId, BitArray), ProtocolError) {
  let handshake_msg = <<
    19:int, "BitTorrent protocol", 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x00,
    0x00, info_hash:bits, peer_id:bits,
  >>
  use _ <- try(mug.send(socket, handshake_msg) |> map_error(TCPError))

  use handshake_back <- try(
    mug.receive_exact(socket, 20 + 8 + 20 + 20, message_timeout)
    |> map_error(TCPError),
  )
  case handshake_back {
    <<
      19:int,
      "BitTorrent protocol",
      reserved:bytes-size(8),
      rev_info_hash:bytes-size(20)-unit(8),
      peer_id:bytes-size(20)-unit(8),
    >> -> {
      case rev_info_hash == info_hash {
        True -> Ok(#(PeerId(peer_id), reserved))
        False -> Error(InfoHashMismatch)
      }
    }
    _ -> Error(InvalidMessage)
  }
}

pub fn send_extended_handshake(
  socket: mug.Socket,
) -> Result(Nil, ProtocolError) {
  let extensions = [#("ut_metadata", 10)]
  let ext_message = Handshake(extensions: extensions)

  let id = message_id(Extension(ext_message))
  let ext_message_id = extension_message_id(ext_message)
  let encoded = encode_extension_message(ext_message)

  let message_len = 1 + 1 + bit_array.byte_size(encoded)
  let extension_message = <<
    message_len:big-size(32),
    id:int,
    ext_message_id:int,
    encoded:bits,
  >>

  send_message(socket, extension_message)
}

fn encode_extension_message(message: ExtensionMessage) {
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
  }
}

pub fn log(m: PeerMessage) {
  case m {
    Piece(_, _, _) -> Piece(..m, block: <<>>)
    _ -> m
  }
}

pub fn send_message(
  socket: mug.Socket,
  message: BitArray,
) -> Result(Nil, ProtocolError) {
  mug.send(socket, message) |> map_error(TCPError)
}

pub fn receive_message(
  socket: mug.Socket,
) -> Result(PeerMessage, ProtocolError) {
  use bits <- try(
    mug.receive_exact(socket, 4, message_timeout) |> map_error(TCPError),
  )
  let assert <<message_length:unsigned-big-size(4)-unit(8)>> = bits

  case message_length {
    // keep alive
    0 -> receive_message(socket)
    _ -> {
      use message <- try(
        mug.receive_exact(socket, message_length, message_timeout)
        |> map_error(TCPError),
      )
      parse_message(message)
    }
  }
}

fn parse_message(message: BitArray) -> Result(PeerMessage, ProtocolError) {
  let assert <<message_id, payload:bits>> = message
  case message_id {
    0 -> Ok(Choke)
    1 -> Ok(Unchoke)
    2 -> Ok(Interested)
    3 -> Ok(NotInterested)
    4 -> Ok(Have)
    5 -> Ok(BitField(payload))
    6 -> {
      case payload {
        <<
          piece_index:big-size(4)-unit(8),
          begin:big-size(4)-unit(8),
          length:big-size(4)-unit(8),
        >> -> Ok(Request(piece_index, begin, length))
        _ -> Error(InvalidMessage)
      }
    }
    7 -> {
      case payload {
        <<
          piece_index:big-size(4)-unit(8),
          begin:big-size(4)-unit(8),
          block:bits,
        >> -> Ok(Piece(piece_index, begin, block))
        _ -> Error(InvalidMessage)
      }
    }
    20 -> parse_extension_message(payload)

    id -> Error(UnknownMessageId(id))
  }
}

fn parse_extension_message(
  message: BitArray,
) -> Result(PeerMessage, ProtocolError) {
  let assert <<extension_id:int, payload:bits>> = message
  case extension_id {
    0 -> {
      use bencode <- try(bencode.decode(payload) |> map_error(BencodeError))

      use dict <- try(
        bencode.dict(bencode)
        |> replace_error(ProtocolErrorMsg(
          "invalid extension handshake response",
        )),
      )
      use entries <- try(
        bencode.get_entries(dict, "m")
        |> replace_error(ProtocolErrorMsg("missing 'm' key in handshake")),
      )
      use extensions <- try(
        list.try_map(entries, fn(entry) {
          case entry {
            #(key, bencode.BInteger(int)) -> Ok(#(key, int))
            _ -> Error(ProtocolErrorMsg("invalid type inside 'm' dictionary"))
          }
        }),
      )
      Extension(Handshake(extensions)) |> Ok
    }
    _ -> Error(UnknownMessageId(extension_id))
  }
}

pub fn message_id(message: PeerMessage) -> Int {
  case message {
    Choke -> 0
    Unchoke -> 1
    Interested -> 2
    NotInterested -> 3
    Have -> 4
    BitField(_) -> 5
    Request(..) -> 6
    Piece(..) -> 7
    Extension(..) -> 20
  }
}

pub fn extension_message_id(message: ExtensionMessage) -> Int {
  case message {
    Handshake(_) -> 0
  }
}

pub type ProtocolError {
  InvalidMessage
  InfoHashMismatch
  TCPError(mug.Error)
  UnknownMessageId(Int)
  UnexpectedMessage(Int)
  ProtocolErrorMsg(String)
  BencodeError(bencode.BencodeError)
}

pub fn describe_error(error: ProtocolError) -> String {
  case error {
    InvalidMessage -> "Received an invalid message from the peer"
    InfoHashMismatch -> "Peer responded with a different info hash"
    UnknownMessageId(msg_id) -> "Unknown Message Id " <> int.to_string(msg_id)
    UnexpectedMessage(msg_id) ->
      "Unexpected peer message: " <> int.to_string(msg_id)
    TCPError(err) -> mug.describe_error(err)
    BencodeError(err) -> bencode.describe_error(err)
    ProtocolErrorMsg(err) -> err
  }
}
