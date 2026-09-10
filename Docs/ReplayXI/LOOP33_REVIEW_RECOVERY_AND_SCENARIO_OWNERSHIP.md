# Loop 33 — save recovery and scenario ownership

## Fixes

### Read errors do not roll back saved reviews

The library previously treated every primary-file read error as corruption.
A valid but temporarily unreadable file could be moved aside and replaced by
an older backup, dropping the newest reviews from the active library.

Only decoding or document-validation failures now trigger damaged-file
recovery. Permission, protection and other I/O failures keep the primary in
place and make the library read-only. Reopening after access is restored loads
the original reviews. Actual corrupt-file recovery and newer-schema protection
are unchanged.

### Shared scenario changes keep the correct annotations

A physical-placement update could force a locally paused follower from match
playback into Shape Focus, then return before adopting the new marks and time.
Autosave consequently filed the old marks under the new scenario. Normal remote
scenario changes also discarded the outgoing scenario's retained marks.

Remote scenario changes now retain outgoing committed marks before changing
the scenario ID. A forced placement switch adopts all matching scenario fields
together and remains paused. Same-scenario comfort review still keeps its own
time, marks and speed.

## Verification

- Tests-first run: all three new bug-reproduction tests failed, with no skips.
  `/private/tmp/replayxi-loop33-red.xcresult` is a completed result bundle.
- One additional test protects same-scenario physical comfort pause.
- The read-failure test uses a unique temporary folder and a valid primary plus
  older backup. It makes the primary unreadable, then checks that both files
  remain unchanged and that reopening after access returns the newest reviews.
- Shared-state tests check both the active replay and a fresh disk-loaded
  library, then verify that returning to solo review restores the old marks.
- Fixed-code full visionOS 27 Simulator suite: **352 passed, 1 skipped,
  0 failed**. All four added tests ran and passed; the existing optional skip
  is unrelated. `/private/tmp/replayxi-loop33-green.xcresult`.
- Simulator Debug and physical-device-target Release builds passed. The latest
  app was relaunched in normal persistent-save mode in Simulator.
- Swift parse and `git diff --check` passed.
- No graphical or gesture-input changes. Multi-headset testing and the prior
  post-fit head visual check remain separate, unverified hardware/UI work.
- No Git push attempted; the existing exact-destination approval request is
  unchanged.
