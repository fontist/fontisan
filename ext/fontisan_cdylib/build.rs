//! Embeds the engine rev this binary is compiled against, read from the
//! `fontisan` dependency's `rev = "..."` in this crate's own Cargo.toml (the
//! one place a repin edits), as `FONTISAN_ENGINE_REV`. The Ruby side compares
//! it with `Fontisan::Native::ENGINE_REV`, so a binary built from an older pin
//! counts as unavailable instead of serving old behaviour.
use std::{env, fs, path::PathBuf};

fn main() {
    let manifest = PathBuf::from(env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR"))
        .join("Cargo.toml");
    println!("cargo:rerun-if-changed={}", manifest.display());
    let text = fs::read_to_string(&manifest).expect("read Cargo.toml");
    let rev = text
        .lines()
        .filter(|line| line.trim_start().starts_with("fontisan") && line.contains("git"))
        .find_map(|line| {
            let tail = line.split("rev").nth(1)?;
            tail.split('"').nth(1).map(str::to_owned)
        })
        .expect("the fontisan dependency in Cargo.toml must carry `rev = \"<sha>\"`");
    println!("cargo:rustc-env=FONTISAN_ENGINE_REV={rev}");
}
