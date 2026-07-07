import gleam/option.{type Option, None, Some}
import gleam/result

pub type File

@external(erlang, "file_ffi", "open")
fn open(filename: String) -> Result(File, String)

@external(erlang, "file_ffi", "allocate")
fn allocate(file: File, size: Int) -> Result(Nil, String)

@external(erlang, "file_ffi", "pwrite")
fn pwrite(file: File, offset: Int, data: BitArray) -> Result(Nil, String)

pub type Writer {
  Writer(
    file: Option(File),
    write: fn(Writer, Int, BitArray) -> Result(Nil, String),
  )
}

pub fn new_file_writer(file_path: String, file_size: Int) -> Writer {
  Writer(file: None, write: fn(writer, offset, data) {
    case writer.file {
      Some(file) -> pwrite(file, offset, data)
      None -> {
        use file <- result.try(open(file_path))
        use _ <- result.try(allocate(file, file_size))
        pwrite(file, offset, data)
      }
    }
  })
}
