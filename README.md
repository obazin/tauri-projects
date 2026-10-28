# tauri-projects

One dev shell, and one AI agent harness, for every Tauri 2 + Svelte 5 project in `~/dev/projects`.

## Why

A Tauri app needs more than a Rust shell: Node and pnpm, the frontend language servers, the webview stack on Linux, and the standard library of every triple the app ships on so per-OS code can be type-checked from one host. Each project used to assemble that itself, and the copies drifted. This flake is a library on top of [rust-projects](https://github.com/obazin/rust-projects): the Rust pin stays there, and bumping it moves every Tauri project with every Rust project.

The same applies to the agent configuration. Each project needs the same rules, MCP servers, permissions, hooks, review agent and workflow commands, so the shell copies them in wherever a file is missing.

## Consuming it

```nix
{
  description = "my-app — …";

  inputs.tauri-projects.url = "github:obazin/tauri-projects";

  outputs =
    { tauri-projects, ... }:
    tauri-projects.forEachSystem (
      lib:
      lib.mkTauriProject {
        name = "my-app";
      }
    );
}
```

with `use flake` in `.envrc`, or start from the template: `nix flake init -t github:obazin/tauri-projects`. That yields `devShells.default` and `formatter` on every system rust-projects supports. There is no package or `checks`: a Tauri bundle needs the frontend build and platform signing, which belong to the project's release flow.

Do **not** commit a `rust-toolchain.toml`. The shell creates one at the project root as a symlink into the Nix store, carrying rust-projects' channel and the cross targets, so rustup and Nix agree. A real file is never overwritten.

## The AI agent harness

On every shell entry, `bootstrap-ai-harness` walks [`harness/`](harness) and creates each file the project does not have:

| File                                   | What it is                                                                                                                                                         |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `CLAUDE.md`                            | Mandatory rules: Svelte autofixer after each `.svelte` edit, runes only, live docs, IPC review, docs current and present-tense, cross-platform facades, AST/LSP search, green checks, no lock-file edits |
| `.mcp.json`                            | The Svelte MCP server (context7 comes from the user-level plugin)                                                                                                  |
| `.claude/settings.json`                | Permission allow-list for pnpm, just, cargo, ast-grep and the Svelte/context7 tools; `feature-dev` plugin; a background `pnpm check` after `.svelte`/`.ts` edits; a hook refusing lock-file edits |
| `.claude/agents/rust-ipc-reviewer.md`  | Adversarial review of the Tauri command surface: unvalidated paths, lock misuse, blocking async work, panics, unbounded input, serde contract, registration and capabilities, cross-platform behaviour |
| `.claude/commands/implement-issue.md`  | `/implement-issue #N`: branch, plan, atomic commits, `/code-review` loop until clean                                                                               |

`@name@` is replaced by the shell name and `@description@` by `package.json`'s `description`. The files are meant to be edited and committed: once a file exists, the project's version wins and is never touched again. The shell prints what it created.

Options on `mkTauriProject` / `mkTauriShell`:

| Option                 | Default | Effect                                                                                                    |
| ---------------------- | ------- | --------------------------------------------------------------------------------------------------------- |
| `aiHarness`            | `true`  | Run the bootstrap on shell entry                                                                          |
| `aiHarnessExclude`     | `[ ]`   | Paths never to create, e.g. `[ ".claude/commands/implement-issue.md" ]` for a project that removed it     |
| `extra`                | `[ ]`   | Extra packages (`lib.pkgs.duckdb`, …)                                                                     |
| `env`                  | `{ }`   | Extra environment variables                                                                               |
| `hook`                 | `""`    | Extra shell hook, run before the zsh re-exec                                                              |
| `materializeToolchain` | `true`  | Create the `rust-toolchain.toml` symlink                                                                  |
| `materializePrettierConfig` | `true` | Link the shared `.prettierrc.json` (4-space, single quotes, width 100, no plugins) unless the project commits its own |
| `zsh`                  | `true`  | Re-exec interactive shells into zsh                                                                       |

`bootstrap-ai-harness <name> [excluded path…]` is also on `PATH`, to recreate a file deleted by mistake.

## What the shell provides

- Everything [rust-projects' shell](https://github.com/obazin/rust-projects#what-the-shell-provides) provides: pinned toolchain with rust-analyzer, cargo tools, nixd/marksman/taplo, sccache, `CARGO_HOME` in the project.
- The standard library for macOS, Windows and Linux on x86_64 and aarch64: `cargo check --target <triple>` type-checks any `#[cfg]` branch. Crates whose build scripts probe system libraries through pkg-config (such as `libdbus-sys` on Linux) still need that platform.
- Node 22, pnpm, typescript-language-server, vtsls, svelte-language-server, tailwindcss-language-server.
- git, just, ripgrep, fd, jq, zsh, ast-grep.
- `run`, a wrapper for `just run`.
- A shared `.prettierrc.json`, linked at the project root unless the project commits one (gitignore it otherwise).
- On Linux: GTK 3, WebKitGTK 4.1, libsoup 3, glib-networking and friends, with `GIO_MODULE_DIR`, `XDG_DATA_DIRS` and `WEBKIT_DISABLE_DMABUF_RENDERER=1`.

## Library API

`tauri-projects.lib.${system}` exposes `mkTauriProject`, `mkTauriShell`, `bootstrapHarness`, `toolchain`, `toolchainFile`, `crossTargets`, the tool sets (`commonTools`, `nodeTools`, `webviewTools`, `shorthands`), `webviewEnv`, `pkgs`, and `rust` (rust-projects' lib for the same system). `tauri-projects.forEachSystem` transposes a per-system function into flake output shape.

## Bumping

```sh
nix flake update rust-projects   # here, after a Rust bump in rust-projects
# then in each consumer
nix flake update tauri-projects
```

Editing a harness file here changes only projects that do not have that file yet; existing projects keep their committed copies.
