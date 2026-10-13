# Manual build policy

- Finish the entire requested change set, update affected documentation, and perform the available fast local lint and static checks before starting GitHub Actions.
- A commit or push must not compile Tinycast automatically. After the completed change set is pushed, manually dispatch Verify for build and test feedback; dispatch Personal build when a distributable app is needed. Do not dispatch either workflow for intermediate commits.
- Confirm each run targets the intended commit and report its result. A queued or running workflow is not a successful build.
