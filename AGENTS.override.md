# Local fork instructions

- Read the tracked `AGENTS.md` and its referenced project documentation before changing code. Codex loads this override instead of the root `AGENTS.md`, so load the shared rules explicitly.
- Use `AGENTS.md` for the original project instructions, but follow `AGENTS.override.md` wherever the two conflict.
- Read `README.override.md` before planning changes to this fork. Treat its implementation descriptions as a snapshot to verify against the current source, not as proof of current runtime behavior.
- Read `agents.local.md` before using GitHub Actions; it defines when to dispatch this fork's builds manually.
- Do not compile or build Tinycast on this Mac, including with `xcodebuild` or compilation-based Swift test harnesses. The required Xcode 26 SDK is large and may be absent locally; use the existing GitHub Actions workflows for compilation and build feedback. Do not install Xcode or the SDK for this fork's work.
- Before committing source changes, review the affected code carefully and prefer fast local lint and static checks. Run only focused tests that address a concrete risk; avoid the full local test suite by default. If local lint requires an unavailable SDK or SourceKit component, use the static checks that can run and report the limitation. Let GitHub Actions handle build validation and any CI test gates.
- For each user-requested fork feature, keep one concise, English entry in `README.override.md` covering the requirement, implementation approach, key APIs and source paths, and material limits. Update that entry as the feature evolves; do not split its implementation steps, commits, CI workflow, or test history into separate requirements.
- Keep `README.override.md` aligned with the code when changing or removing an earlier fork requirement. Never turn an unresolved observation into a claimed guarantee.
