//! The engine's C ABI (`fontisan_call`, `fontisan_result_free`,
//! `fontisan_abi_version`) re-exported so this cdylib exports the symbols.
//! Without the glob re-export the library links empty; CI checks the exports
//! with `nm -gU` / `dumpbin /exports`.
pub use fontisan::ffi::*;

/// The engine rev this library was compiled against (see `build.rs`), as a
/// NUL-terminated static string. The Ruby `:ffi` tier refuses a library that
/// lacks this symbol or reports another rev than `Fontisan::Native::ENGINE_REV`.
#[no_mangle]
pub extern "C" fn fontisan_cdylib_engine_rev() -> *const std::ffi::c_char {
    concat!(env!("FONTISAN_ENGINE_REV"), "\0").as_ptr().cast()
}
