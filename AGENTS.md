# Repository boundaries

This repository manages large vendored third-party libraries for LAB.

- Never recursively enumerate or search the entire repository or `baseLibs`.
- Start with top-level listings and the explicit paths in `dependencies.json`.
- Inspect only the selected library's build entrypoints and files needed for a concrete problem.
- Do not edit vendored source to fix orchestration. Put adapters in `cmake/` or `scripts/`.
- Keep generated files under `.build/` and new outputs under `result/`.
- Preserve existing hand-built `result/libHeaders` and `result/libs`.
- `createAndroidLibs` is out of scope for the Windows build experiment.
- Do not run blanket formatters, source hash crawls, or repository-wide recursive file searches.
