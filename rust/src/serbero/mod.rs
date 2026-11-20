//! Serbero's mediation reports (D13): what Serbero, the assistant Read
//! solver, sends to this solver key when it hands a dispute off.
//!
//! Serbero mediates with its own key, so its chat with the parties is keyed
//! between Serbero and each trade key and cannot be opened here. At handoff it
//! sends the solver a brief, the whole conversation as a transcript, the
//! messages that arrive after the handoff, and a final report. Each one is a
//! Mostro v2 `send-dm` message in a NIP-44 kind 14 event signed by Serbero
//! (Serbero's `docs/messages.md` §3).
//!
//! **What is taken** ([`intake`]): only an event from the Serbero pubkey the
//! solver trusts on the active node, opened with the loaded key, whose sender
//! is that same pubkey, with action `send-dm` and a text payload, and whose
//! first line names the dispute of the message id ([`parse`]). Anything else
//! is dropped, and none of it is ever treated as a protocol action. The
//! content is never logged.

pub(crate) mod intake;
pub(crate) mod parse;
