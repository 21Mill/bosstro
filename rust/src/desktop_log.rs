//! Rust logs on the desktop (Linux, for development: A2).
//!
//! flutter_rust_bridge's `setup_default_user_utils` installs a logger on
//! Android (logcat), iOS / macOS (os_log) and the web (the console), and none
//! anywhere else: on Linux every `log::info!` of the core went nowhere. This
//! writes them to stderr, where `flutter run` shows them.
//!
//! This crate's lines from `info` up, other crates' from `warn` up: the relay
//! library is chatty below that. What may be logged is each call site's
//! rule (never a key, a message's content or an order); this only prints.

use log::{Level, LevelFilter, Log, Metadata, Record};

struct StderrLogger;

/// This crate's module path prefix, as `log` records it.
const OWN: &str = env!("CARGO_CRATE_NAME");

fn wanted(metadata: &Metadata) -> bool {
    let own = metadata.target() == OWN
        || metadata
            .target()
            .strip_prefix(OWN)
            .is_some_and(|rest| rest.starts_with("::"));
    metadata.level() <= if own { Level::Info } else { Level::Warn }
}

impl Log for StderrLogger {
    fn enabled(&self, metadata: &Metadata) -> bool {
        wanted(metadata)
    }

    fn log(&self, record: &Record) {
        if wanted(record.metadata()) {
            eprintln!("[rust] {} {}", record.level(), record.args());
        }
    }

    fn flush(&self) {}
}

/// Install the stderr logger. A no-op when a logger is already set.
pub(crate) fn init() {
    static LOGGER: StderrLogger = StderrLogger;
    if log::set_logger(&LOGGER).is_ok() {
        log::set_max_level(LevelFilter::Info);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn meta(target: &'static str, level: Level) -> Metadata<'static> {
        Metadata::builder().target(target).level(level).build()
    }

    #[test]
    fn this_crate_logs_from_info_and_the_others_from_warn() {
        let own = concat!(env!("CARGO_CRATE_NAME"), "::mostro::order_info");
        assert!(wanted(&meta(own, Level::Info)));
        assert!(wanted(&meta(own, Level::Warn)));
        assert!(!wanted(&meta(own, Level::Debug)));

        assert!(wanted(&meta("nostr_relay_pool::relay", Level::Warn)));
        assert!(!wanted(&meta("nostr_relay_pool::relay", Level::Info)));
        // A crate whose name only starts like this one is another crate.
        let lookalike = concat!(env!("CARGO_CRATE_NAME"), "y::x");
        assert!(!wanted(&meta(lookalike, Level::Info)));
    }
}
