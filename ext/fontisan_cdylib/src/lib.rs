//! The engine's C ABI (`fontisan_call`, `fontisan_result_free`,
//! `fontisan_abi_version`) re-exported so this cdylib exports the symbols.
//! Without the glob re-export the library links empty; CI checks the exports
//! with `nm -gU` / `dumpbin /exports`.
pub use fontisan::ffi::*;
