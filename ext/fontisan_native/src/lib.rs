//! The `:native` tier of the fontisan gem: the fontisan-rs engine through magnus.
//!
//! Division of labour (decided here, see `lib/fontisan/native.rb`):
//! * Rust walks the engine's `Json` documents straight into Ruby Hash / Array /
//!   String / Integer objects. No JSON text is rendered or parsed on either side,
//!   so each batch row is decoded exactly once. Hash keys are inserted bytewise
//!   sorted, like `Reference.normalize`.
//! * The GVL is released around every engine call. Nothing inside the released
//!   section touches Ruby: inputs are copied into owned Rust values first and
//!   the result is plain Rust data until the GVL is back.
//! * A failure is raised as `Fontisan::Native::Failure` carrying the engine's
//!   `[class, message, [[cause class, cause message], ...]]`; the Ruby side
//!   rebuilds the Ruby tier's exception class and cause chain from it. A Rust
//!   panic is caught inside the released section and raised as
//!   `Fontisan::Native::Panic`.
use fontisan::audit;
use fontisan::convert::{self, Target};
use fontisan::json::Json;
use fontisan::read;
use fontisan::scan::{self, RowStatus};
use fontisan::sfnt::{self, Format, LoadingMode, Options};
use fontisan::{instance, subset};
use magnus::value::ReprValue;
use magnus::{function, prelude::*, Error, IntoValue, RArray, RModule, Ruby, Value};
use std::ffi::c_void;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::Path;

/// Bumped on any change to the functions below. `lib/fontisan/native.rb` refuses a
/// mismatch (then the tier is simply unavailable).
const ABI_VERSION: u32 = 1;

/// What the engine reported, before it becomes a Ruby exception.
enum Fail {
    Engine {
        class: String,
        message: String,
        causes: Vec<(String, String)>,
    },
    Panic(String),
}

impl Fail {
    fn simple(class: &str, message: impl Into<String>) -> Self {
        Self::Engine {
            class: class.to_string(),
            message: message.into(),
            causes: Vec::new(),
        }
    }

    /// From an engine `{class, message, causes}` document (`read::error_json`,
    /// `audit::command_error_json`).
    fn from_doc(doc: &Json) -> Self {
        let Json::Obj(members) = doc else {
            return Self::simple("Fontisan::Error", "unreadable engine error");
        };
        let text = |key: &str| match members.iter().find(|(k, _)| *k == key) {
            Some((_, Json::Str(s))) => s.clone(),
            _ => String::new(),
        };
        let causes = match members.iter().find(|(k, _)| *k == "causes") {
            Some((_, Json::Arr(items))) => items
                .iter()
                .filter_map(|item| match item {
                    Json::Obj(m) => {
                        let get = |key: &str| match m.iter().find(|(k, _)| *k == key) {
                            Some((_, Json::Str(s))) => s.clone(),
                            _ => String::new(),
                        };
                        Some((get("class"), get("message")))
                    }
                    _ => None,
                })
                .collect(),
            _ => Vec::new(),
        };
        Self::Engine {
            class: text("class"),
            message: text("message"),
            causes,
        }
    }
}

type Outcome<T> = Result<T, Fail>;

fn panic_text(payload: &(dyn std::any::Any + Send)) -> String {
    if let Some(s) = payload.downcast_ref::<&str>() {
        (*s).to_string()
    } else if let Some(s) = payload.downcast_ref::<String>() {
        s.clone()
    } else {
        "non-string panic payload".to_string()
    }
}

/// Run `work` with the GVL released. `work` must not touch Ruby. A panic in it
/// is caught here, inside the released section, and returned as [`Fail::Panic`].
fn nogvl<T, F>(work: F) -> Outcome<T>
where
    F: FnOnce() -> Outcome<T>,
{
    struct Slot<F, T> {
        work: Option<F>,
        out: Option<Outcome<T>>,
    }
    unsafe extern "C" fn run<T, F: FnOnce() -> Outcome<T>>(data: *mut c_void) -> *mut c_void {
        // SAFETY: `data` is the `Slot` on the caller's stack below; the call
        // blocks until this function returns, so it outlives the call.
        let slot = unsafe { &mut *data.cast::<Slot<F, T>>() };
        let work = slot.work.take().expect("work runs once");
        slot.out = Some(
            catch_unwind(AssertUnwindSafe(work))
                .unwrap_or_else(|p| Err(Fail::Panic(panic_text(&*p)))),
        );
        std::ptr::null_mut()
    }
    let mut slot = Slot {
        work: Some(work),
        out: None,
    };
    // SAFETY: `run::<T, F>` matches the callback type and only touches `slot`.
    unsafe {
        rb_sys::rb_thread_call_without_gvl(
            Some(run::<T, F>),
            std::ptr::addr_of_mut!(slot).cast(),
            None,
            std::ptr::null_mut(),
        );
    }
    slot.out.expect("the callback always stores an outcome")
}

fn module(ruby: &Ruby) -> Result<RModule, Error> {
    let fontisan = ruby.define_module("Fontisan")?;
    fontisan.define_module("Native")
}

/// Raise `Fontisan::Native::Failure` / `Panic` for a [`Fail`].
fn raise(ruby: &Ruby, fail: Fail) -> Error {
    let result = (|| -> Result<Error, Error> {
        let native = module(ruby)?;
        match fail {
            Fail::Panic(text) => {
                let class: magnus::ExceptionClass = native.const_get("Panic")?;
                Ok(Error::new(class, format!("engine panic: {text}")))
            }
            Fail::Engine {
                class,
                message,
                causes,
            } => {
                let klass: magnus::ExceptionClass = native.const_get("Failure")?;
                let exc: Value = klass.funcall("new", (message.as_str(),))?;
                let causes_rb = ruby.ary_new_capa(causes.len());
                for (c, m) in &causes {
                    let pair = ruby.ary_new_capa(2);
                    pair.push(ruby.str_new(c))?;
                    pair.push(ruby.str_new(m))?;
                    causes_rb.push(pair)?;
                }
                let details = ruby.ary_new_capa(3);
                details.push(ruby.str_new(&class))?;
                details.push(ruby.str_new(&message))?;
                details.push(causes_rb)?;
                exc.funcall::<_, _, Value>("instance_variable_set", ("@details", details))?;
                let exception = magnus::Exception::from_value(exc)
                    .ok_or_else(|| Error::new(ruby.exception_runtime_error(), "bad failure"))?;
                Ok(Error::from(exception))
            }
        }
    })();
    result.unwrap_or_else(|e| e)
}

fn finish<T>(ruby: &Ruby, outcome: Outcome<T>) -> Result<T, Error> {
    outcome.map_err(|fail| raise(ruby, fail))
}

/// Engine document -> Ruby objects, keys bytewise sorted.
fn to_value(ruby: &Ruby, json: &Json) -> Result<Value, Error> {
    Ok(match json {
        Json::Null => ruby.qnil().as_value(),
        Json::Bool(true) => ruby.qtrue().as_value(),
        Json::Bool(false) => ruby.qfalse().as_value(),
        Json::Int(i) => i.into_value_with(ruby),
        Json::Str(s) => ruby.str_new(s).as_value(),
        Json::Arr(items) => {
            let array = ruby.ary_new_capa(items.len());
            for item in items {
                array.push(to_value(ruby, item)?)?;
            }
            array.as_value()
        }
        Json::Obj(members) => {
            hash(ruby, members.iter().map(|(k, v)| (*k, v)).collect())?
        }
        Json::Map(members) => {
            hash(ruby, members.iter().map(|(k, v)| (k.as_str(), v)).collect())?
        }
    })
}

fn hash(ruby: &Ruby, mut members: Vec<(&str, &Json)>) -> Result<Value, Error> {
    members.sort_by(|a, b| a.0.as_bytes().cmp(b.0.as_bytes()));
    let out = ruby.hash_new();
    for (key, value) in members {
        out.aset(ruby.str_new(key), to_value(ruby, value)?)?;
    }
    Ok(out.as_value())
}

fn rows(ruby: &Ruby, docs: &[Json]) -> Result<RArray, Error> {
    let array = ruby.ary_new_capa(docs.len());
    for doc in docs {
        array.push(to_value(ruby, doc)?)?;
    }
    Ok(array)
}

fn read_file(path: &str) -> Outcome<Vec<u8>> {
    std::fs::read(path).map_err(|e| {
        let class = if e.kind() == std::io::ErrorKind::NotFound {
            "Errno::ENOENT"
        } else {
            "IOError"
        };
        Fail::simple(class, format!("{e} - {path}"))
    })
}

fn bytes_value(ruby: &Ruby, bytes: &[u8]) -> Value {
    let s = ruby.str_from_slice(bytes);
    // A binary String, like the Ruby tier's `FontWriter` output.
    let _ = s.funcall::<_, _, Value>("force_encoding", ("BINARY",));
    s.as_value()
}

// --- read-type ops -------------------------------------------------------

fn native_read(ruby: &Ruby, path: String, metadata: bool, lazy: bool) -> Result<RArray, Error> {
    let options = Options {
        mode: if metadata {
            LoadingMode::Metadata
        } else {
            LoadingMode::Full
        },
        lazy,
    };
    let docs = finish(
        ruby,
        nogvl(move || {
            let bytes = read_file(&path)?;
            read::read(&bytes, options).map_err(|e| Fail::from_doc(&read::error_json(&e)))
        }),
    )?;
    rows(ruby, &docs)
}

fn native_audit(ruby: &Ruby, path: String, validate: bool) -> Result<RArray, Error> {
    let docs = finish(
        ruby,
        nogvl(move || {
            let bytes = read_file(&path)?;
            let name = Path::new(&path)
                .file_name()
                .map_or_else(|| path.clone(), |n| n.to_string_lossy().into_owned());
            let reports = audit::audit_staged(&bytes, &name, validate)
                .map_err(|(e, stage)| Fail::from_doc(&audit::command_error_json(&e, stage)))?;
            Ok(reports.iter().map(audit::Report::to_json).collect::<Vec<_>>())
        }),
    )?;
    rows(ruby, &docs)
}

/// Scan rows of one file (no "status" key on supported rows, like the Ruby tier).
fn native_scan(ruby: &Ruby, path: String) -> Result<RArray, Error> {
    let docs = finish(
        ruby,
        nogvl(move || {
            Ok(scan::scan_path(Path::new(&path))
                .iter()
                .map(|row| match (row.status, row.to_json()) {
                    (RowStatus::Ok, Json::Obj(members)) => {
                        Json::Obj(members.into_iter().filter(|(k, _)| *k != "status").collect())
                    }
                    (_, doc) => doc,
                })
                .collect::<Vec<_>>())
        }),
    )?;
    rows(ruby, &docs)
}

/// One engine row per font file below `dir` (see `audit::dir_row`).
fn native_audit_dir_rows(ruby: &Ruby, dir: String, validate: bool) -> Result<RArray, Error> {
    let docs = finish(
        ruby,
        nogvl(move || {
            let files = scan::font_files(Path::new(&dir))
                .map_err(|e| Fail::simple("IOError", format!("cannot read {dir}: {e}")))?;
            Ok(files
                .iter()
                .map(|file| audit::dir_row(file, validate))
                .collect::<Vec<_>>())
        }),
    )?;
    rows(ruby, &docs)
}

/// Whether the engine reads the file itself: false for a file that is gone, a
/// directory, dfont, Type 1 and anything that is not a font (the Ruby tier serves those).
fn native_supports_file(ruby: &Ruby, path: String) -> Result<bool, Error> {
    finish(
        ruby,
        nogvl(move || {
            use std::io::Read;
            let Ok(file) = std::fs::File::open(&path) else {
                return Ok(false);
            };
            let mut head = Vec::new();
            if file.take(256).read_to_end(&mut head).is_err() {
                return Ok(false);
            }
            // Not a font at all (random bytes, a zero-filled or empty file): the
            // Ruby tier raises the canonical InvalidFontError, and the engine never
            // slurps a huge non-font into memory. A `ttcf` file whose directory lies
            // past the 256-byte head is a font the engine reads itself.
            let unknown = sfnt::detect_format(&head).is_none() && !head.starts_with(b"ttcf");
            Ok(!unknown
                && !matches!(
                    sfnt::detect_format(&head),
                    Some(Format::Dfont | Format::Pfa | Format::Pfb)
                ))
        }),
    )
}

// --- byte ops (path based; the Ruby gates for these are card 2f) ----------

fn convert_failed(e: &convert::ConvertError) -> Fail {
    Fail::simple(e.class, e.message.clone())
}

fn native_convert(ruby: &Ruby, path: String, target: u32, timestamp: i64) -> Result<Value, Error> {
    let bytes = finish(
        ruby,
        nogvl(move || {
            let target = Target::from_code(target)
                .ok_or_else(|| Fail::simple("ArgumentError", format!("unknown target {target}")))?;
            let input = read_file(&path)?;
            convert::convert(&input, target, timestamp).map_err(|e| convert_failed(&e))
        }),
    )?;
    Ok(bytes_value(ruby, &bytes))
}

/// `[basename, bytes]` of one collection member.
fn native_extract(ruby: &Ruby, path: String, index: usize) -> Result<RArray, Error> {
    let (name, data) = finish(
        ruby,
        nogvl(move || {
            let input = read_file(&path)?;
            let x = convert::extract(&input, index).map_err(|e| convert_failed(&e))?;
            Ok((x.basename, x.data))
        }),
    )?;
    let out = ruby.ary_new_capa(2);
    out.push(ruby.str_new(&name))?;
    out.push(bytes_value(ruby, &data))?;
    Ok(out)
}

/// `coords`: `[[tag, value], ...]` with a 4-byte tag.
fn native_instance(ruby: &Ruby, path: String, coords: Vec<(String, f64)>) -> Result<Value, Error> {
    let bytes = finish(
        ruby,
        nogvl(move || {
            let mut axes = Vec::with_capacity(coords.len());
            for (tag, value) in &coords {
                let tag: [u8; 4] = tag
                    .as_bytes()
                    .try_into()
                    .map_err(|_| Fail::simple("ArgumentError", format!("bad axis tag {tag:?}")))?;
                axes.push((tag, *value));
            }
            let input = read_file(&path)?;
            instance::instance(&input, &axes).map_err(|e| convert_failed(&e))
        }),
    )?;
    Ok(bytes_value(ruby, &bytes))
}

fn native_subset(ruby: &Ruby, path: String, gids: Vec<u32>, profile: String) -> Result<Value, Error> {
    let bytes = finish(
        ruby,
        nogvl(move || {
            let input = read_file(&path)?;
            subset::subset(&input, &gids, &profile)
                .map_err(|e| Fail::simple(e.class, e.message.clone()))
        }),
    )?;
    Ok(bytes_value(ruby, &bytes))
}

/// Glyph ids kept for `codepoints` (the facade's `gids_for`); `name` is the
/// file's basename, used in the "None of the requested characters" error.
fn native_glyph_ids(ruby: &Ruby, path: String, codepoints: Vec<u32>, name: String) -> Result<Vec<u32>, Error> {
    finish(
        ruby,
        nogvl(move || {
            let input = read_file(&path)?;
            subset::glyph_ids_for(&input, &codepoints, &name)
                .map_err(|e| Fail::simple(e.class, e.message.clone()))
        }),
    )
}

// --- probes --------------------------------------------------------------

/// Seeded failure for the specs: panics inside the released section.
fn native_selftest_panic(ruby: &Ruby) -> Result<(), Error> {
    finish(
        ruby,
        nogvl(|| -> Outcome<()> { panic!("seeded panic (selftest)") }),
    )
}

/// Holds the engine call open for `millis` with the GVL released, so a spec can
/// prove another Ruby thread keeps running (the sleep stands in for a long scan).
fn native_selftest_block(ruby: &Ruby, millis: u64) -> Result<(), Error> {
    finish(
        ruby,
        nogvl(move || {
            std::thread::sleep(std::time::Duration::from_millis(millis));
            Ok(())
        }),
    )
}

fn extension_abi_version() -> u32 {
    ABI_VERSION
}

/// The engine rev this build was compiled against (see `build.rs`).
fn extension_engine_rev() -> &'static str {
    env!("FONTISAN_ENGINE_REV")
}

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let native = module(ruby)?;
    native.define_singleton_method("extension_abi_version", function!(extension_abi_version, 0))?;
    native.define_singleton_method("extension_engine_rev", function!(extension_engine_rev, 0))?;
    native.define_singleton_method("native_read", function!(native_read, 3))?;
    native.define_singleton_method("native_audit", function!(native_audit, 2))?;
    native.define_singleton_method("native_scan", function!(native_scan, 1))?;
    native.define_singleton_method("native_audit_dir_rows", function!(native_audit_dir_rows, 2))?;
    native.define_singleton_method("native_supports_file", function!(native_supports_file, 1))?;
    native.define_singleton_method("native_convert", function!(native_convert, 3))?;
    native.define_singleton_method("native_extract", function!(native_extract, 2))?;
    native.define_singleton_method("native_instance", function!(native_instance, 2))?;
    native.define_singleton_method("native_subset", function!(native_subset, 3))?;
    native.define_singleton_method("native_glyph_ids", function!(native_glyph_ids, 3))?;
    native.define_singleton_method("native_selftest_panic", function!(native_selftest_panic, 0))?;
    native.define_singleton_method("native_selftest_block", function!(native_selftest_block, 1))?;
    Ok(())
}
