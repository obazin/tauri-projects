{
  description = "CHANGEME — a Tauri app";

  # The dev shell lives in tauri-projects: the Rust pin (from rust-projects),
  # the cross targets, Node, the webview stack and the AI agent harness, which
  # is copied into this directory on shell entry wherever a file is missing.
  # Do not add a rust-toolchain.toml: the shell materializes the shared one.
  inputs.tauri-projects.url = "github:obazin/tauri-projects";

  outputs =
    { tauri-projects, ... }:
    tauri-projects.forEachSystem (
      lib:
      lib.mkTauriProject {
        name = "CHANGEME";

        # Native dependencies go here, e.g.:
        # extra = [ lib.pkgs.duckdb ];
      }
    );
}
