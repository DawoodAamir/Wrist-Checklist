# Contributing

Use Xcode 27 and Swift 6. Preserve atomic commits, bounded payload validation, deterministic edit ordering, and retained archive records. Never replace the store with an unvalidated incoming snapshot.

Run Debug and Release core tests and build all targets. Test offline edits on both devices, reconnection, Watch switching, notification changes, and complication refresh on paired hardware. Do not commit signing identities, personal checklist data, build output, or provisioning profiles.

Use focused Conventional Commits and describe user-visible behavior and actual verification.
