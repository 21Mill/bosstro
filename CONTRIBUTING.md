# Contributing

Anyone is welcome to contribute to Bosstro. If you are looking for somewhere to start, look at
the [open issues](https://github.com/MostroP2P/bosstro/issues).

Bosstro is a mobile app for Mostro dispute solvers: a **Rust** core (Nostr, cryptography, keys,
persistence, business logic) with a **Flutter** UI, bridged by `flutter_rust_bridge`. Read
[AGENTS.md](AGENTS.md) before contributing: it has the architecture, the decisions behind it,
the protocol notes, the key handling rules and the commands. This guide is about how to
contribute; AGENTS.md is about what the code must keep.

The practices below are a guide, not a gate: nothing here is checked by a bot, and no pull
request is closed for missing a section. They are what makes a change quick to review and safe
to merge, and reviewers will ask for them.

## Language

Everything in the repository is written in **English**: code, comments, identifiers, commit
messages, branch names, pull request titles and descriptions, review comments, issues and docs.
The only exception is user-facing copy, which lives in the l10n ARB files
(`lib/l10n/app_en.arb` is the source).

## Communication channels

Most technical discussion happens on the development [Telegram group](https://t.me/mostro_dev);
non-technical discussion happens on the [Mostro Telegram group](https://t.me/MostroP2P).
Discussion about code changes happens in GitHub issues and pull requests.

Do not report a vulnerability in a public issue: report it privately, as
[SECURITY.md](SECURITY.md) explains.

## Contributor workflow

All changes come in through pull requests:

- Fork the repository.
- Create a topic branch from `main`, named `type/kebab-desc` (`feat/order-filters`,
  `fix/slow-relay-waits`).
- Commit with [conventional commits](https://www.conventionalcommits.org/) (`feat`, `fix`,
  `docs`, `refactor`, `chore`, `test`, …), with an optional scope.
- Squash redundant commits and the ones added after a review.
- Open a pull request from your branch to `main`.
- Make the changes reviewers ask for and request a new review.

Keep a pull request to **one change**. Do not mix a refactoring with a fix, or a fix with a
feature. A long feature is split into pull requests that each build, pass the tests and can be
reviewed on their own.

A pull request's **title** is its line in the release notes and in `CHANGELOG.md`: write it for
the solver who reads the release, not for the reviewer. Entries are grouped by the title's
conventional-commit type (`tool/release_notes.dart`, [docs/RELEASING.md](docs/RELEASING.md)),
so the title needs its prefix.

## Before you write code

- **Talk about it in an issue first** when the change is more than a small fix. "This is not a
  bug" or "this is not the design we want" costs one comment there, and a whole review in a
  pull request. Link the issue from the pull request with a closing keyword (`Closes #123`).
- **Read the reference before asserting how it works.** Bosstro follows
  [`app`](https://github.com/MostroP2P/app) for architecture and style,
  [Mostrix](https://github.com/MostroP2P/mostrix) for the admin flows, and the daemon,
  [`mostro`](https://github.com/MostroP2P/mostro), for the protocol.
- **Respect the golden rule.** Rust owns the Nostr protocol, cryptography, keys, relays,
  persistence and business logic; Dart owns the UI, navigation, UI state and device I/O. No
  cryptography in Dart, and Rust does not translate: it returns data or a stable marker, and
  Dart maps it to a localized string.

## Changes that deserve extra care

Some parts of Bosstro cannot be fixed after the fact. A change there should say, in its
description, why it is safe:

- **Resolution** (`AdminSettle` / `AdminCancel`): a settle cannot be undone. Nothing is ever
  retried, and a request that left is never read as "not sent".
- **The solver key**: how it is stored, crosses the bridge, is held in Rust, is shown and is
  copied ("Key handling" in AGENTS.md).
- **What is sent to a relay or a server**: event kinds, tags, message formats, the chat
  envelope, attachments and, once notifications land, the push wake. State the impact on what
  reads them: the daemon, `app`, Mostrix and relays.
- **What is stored or logged**: the database is not encrypted, so a change that stores or logs
  something new says what it is and why it may be kept. A message's content, a key and a
  party's trade pubkey are never logged.
- **Storage**: never edit a migration that shipped; add a new file. A change to anything
  persisted is tried as an upgrade of an install made by `main`.

## A good pull request

A pull request should show two things before a reviewer reads the diff: that the problem it
addresses exists, and that the change does not break something else. A description that does
this well says:

- **What changes and why**, in a few sentences, and the issue it closes.
- **The affected flow**: the screens and the solver's actions it touches (take a dispute,
  write to a party, pay the buyer, look up an order…), the dispute statuses involved, and
  where that behaviour lives: Rust core, bridge (`rust/src/api/`) or Dart.
- **What else could be affected**: what reads or writes the state you changed (stored data and
  installs upgrading, generated bindings, the other platforms, localization keys, what the
  daemon and the parties' apps see), and why it is not broken.
- **How it was tested**, and **what was not** (see below). If you could not build or run the
  app, say so instead of claiming results.
- **Differences from the issue**, when the change does not do exactly what the issue asked.

A description must match its diff. Say plainly what is not included.

### Manual testing

Try the change by hand, in the app built from your branch, and write down what you did so a
reviewer can do the same and see the same:

- **Setup**: how you built the app (platform, device, debug or release), which node and relays,
  which client plays each party, and the state you started from.
- **Steps**, numbered. Each one names an actor (solver, buyer, seller), one action, and what
  you expected to see: a screen, a status, a message, a button enabled or hidden, a dispute's
  status on its public event (kind 38386). A step that cannot be observed ("the router is now
  more robust") is not a step.
- **For a fix**, one step that fails on `main`, saying what `main` does instead.
- **A regression step** on a neighbouring flow, showing it behaves as before.
- **Not covered**: what the steps do not test, and why.

Test against a **local** relay and a local mostrod, never a real node or public relays:
[`integration_test/README.md`](integration_test/README.md) describes the setup and the
end-to-end runs. A change to resolution is tried with real regtest sats, as described there.

### Tests

- A fix comes with a regression test that **fails without the fix and passes with it**. The
  clearest way to show it is a first commit, `test:`, that only adds the test, followed by the
  fix; check it yourself by running the test on `main`.
- A test should be able to fail. An assertion that passes whether or not the behaviour works
  (for example, one that races with a background task) proves nothing: assert what the test
  can observe, and test the rest where it can be observed.
- Tests never reach a public service: use a local server, as the existing tests do (a local
  relay, a local Blossom server).
- Every new screen has a widget test at 2× text, 320 dp, in Spanish, with no overflow, and
  joins `test/l10n/all_locales_fit_test.dart`, which lays it out in every locale: the longest
  translation differs per string.

### Visible changes

- Add **before** (`main`) and **after** (your branch) screenshots of the same screen with the
  same data; both themes when a colour, contrast or layout changes; a short recording when the
  change is inside a flow.
- Name the [design guide](.specify/DESIGN_SYSTEM.md) rules the change touches (`DS-COL-1`,
  `DS-CMP-3`, …), and any SHOULD it departs from and why.
- Never screenshot a real nsec, a real party's messages or their trade keys.

### AI tools

AI tools are allowed. You are responsible for every line you submit and should be able to
explain any of it when a reviewer asks; "the tool wrote it" is not an answer.

## Checks before you push

CI runs these on every pull request. Run them locally first:

```bash
(cd rust && cargo test && cargo clippy -- -D warnings)
flutter analyze && flutter test
dart tool/design_check.dart
./scripts/check-generated.sh
```

Use the toolchain CI uses, listed under [Building](README.md#building) in the README (Flutter,
the Rust that `rust-toolchain.toml` pins, the bridge codegen): the generated code depends on
it, so another version makes the last check fail on files you did not touch.

Do not reformat files you are not changing: it hides the change among unrelated lines.

### Generated code

`lib/src/rust/`, `rust/src/frb_generated.rs` and `lib/l10n/app_localizations*.dart` are
generated and committed. They change only by regenerating them, in the same commit as their
cause; never edit, hand-merge or `dart format` them.

| You changed | Run | Commit together |
|---|---|---|
| anything under `rust/src/api/` | `./scripts/frb-generate.sh` | the source and the generated bindings |
| `lib/l10n/*.arb` | `flutter gen-l10n` | the `.arb` and `lib/l10n/app_localizations*.dart` |

When two branches conflict in a generated file, resolve the sources, take either side of the
generated file, and regenerate. A string is added to **every** ARB file, with the words of the
glossary (design guide §9).

## Commits

Beyond the conventional-commits prefix, follow the
[seven rules of a great commit message](https://chris.beams.io/posts/git-commit/#seven-rules):

1. Separate subject from body with a blank line
2. Limit the subject line to around 50 characters
3. Use the imperative mood in the subject line
4. Do not end the subject line with a period
5. Wrap the body at 72 characters
6. Use the body to explain what and why vs. how
7. Reference relevant issues in the body

Sign your commits ([instructions](https://docs.github.com/en/authentication/managing-commit-signature-verification/signing-commits)).

Keep the history clear and easy to browse: only meaningful commits, and **no merge commits** in
a pull request; rebase on `main` instead.

## Reviewing pull requests

Anyone may take part in peer review, through comments on the pull request. Reviewers check the
code for errors, try the change and give their opinion on its technical merits; maintainers
take that into account when deciding whether to merge. The language used in comments is adapted
from the [Bitcoin Core contributor documentation](https://github.com/bitcoin/bitcoin/blob/master/CONTRIBUTING.md#peer-review):

- `ACK` means "I have tested the code and I agree it should be merged";
- `NACK` means "I disagree this should be merged", and comes with sound technical
  justification. A NACK without reasoning may be disregarded;
- `utACK` means "I have not tested the code, but I have reviewed it and it looks OK";
- `Concept ACK` means "I agree with the general principle of this pull request";
- `Nit` refers to trivial, often non-blocking issues.

A review of a UI change cites design guide rule IDs. A review of a change to an event, a tag or
a message format checks that the daemon, the parties' apps and relays are not silently broken.
