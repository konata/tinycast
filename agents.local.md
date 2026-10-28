# Manual build policy

- Finish the entire requested change set, update affected documentation, and perform the available fast local lint and static checks before starting GitHub Actions.
- A commit or push must not compile Tinycast automatically. After the completed change set is pushed, manually dispatch Verify for build and test feedback; dispatch Personal build when a distributable app is needed. Do not dispatch either workflow for intermediate commits.
- Confirm each run targets the intended commit and report its result. A queued or running workflow is not a successful build.
- Keep `Personal build`'s stable `MARKETING_VERSION` at least the highest upstream release it has merged, plus the `-konata` suffix, so a personal update is never versioned below its upstream base.
- Personal stable versions use `MAJOR.MINOR.PATCH-konata.N`. Keep the triple at the merged upstream release and increment `N` for every published fork build, whether the change came from an upstream merge or fork-only work. `N` never resets: after merging upstream `0.12.4`, `0.12.3-konata.3` is followed by `0.12.4-konata.4`. The app updater accepts only this form, a plain `MAJOR.MINOR.PATCH`, or upstream's `-beta.N`; never invent another suffix.
