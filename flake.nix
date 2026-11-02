{
  description = "Shared Tauri dev environment — rust-projects' toolchain pin plus Node, the webview stack and an AI agent harness";

  # The Rust pin is rust-projects', not ours: this flake adds the cross targets
  # a Tauri app ships on and everything above the Rust layer. nixpkgs comes
  # through rust-projects too, so a Tauri shell and a plain Rust shell resolve
  # the same packages.
  inputs.rust-projects.url = "github:obazin/rust-projects";

  outputs =
    { self, rust-projects }:
    let
      perSystem = builtins.mapAttrs (
        system: rust:
        let
          inherit (rust) pkgs;
          inherit (pkgs) lib stdenv;

          # ── Toolchain ────────────────────────────────────────────────────
          # rust-projects' channel and components, plus the standard library
          # of every triple a Tauri app ships on, so each `#[cfg(target_os)]`
          # branch can be type-checked from any host with
          # `cargo check --target <triple>`. The channel manifest hash covers
          # every target, so rust-projects' sha256 still applies.
          upstreamToolchain = (fromTOML (builtins.readFile rust.toolchainFile)).toolchain;
          crossTargets = [
            "aarch64-apple-darwin"
            "x86_64-apple-darwin"
            "x86_64-pc-windows-msvc"
            "aarch64-pc-windows-msvc"
            "x86_64-unknown-linux-gnu"
            "aarch64-unknown-linux-gnu"
          ];
          toolchainFile = builtins.toFile "rust-toolchain.toml" ''
            # Materialized by tauri-projects from rust-projects' pin. Do not edit:
            # bump Rust in rust-projects.
            [toolchain]
            channel = "${upstreamToolchain.channel}"
            components = ${builtins.toJSON upstreamToolchain.components}
            targets = ${builtins.toJSON crossTargets}
            profile = "minimal"
          '';
          toolchain = rust.mkToolchain {
            file = toolchainFile;
            sha256 = rust.toolchainSha256;
          };

          # ── Tool sets ────────────────────────────────────────────────────
          commonTools = with pkgs; [
            git
            just
            ripgrep
            fd
            jq
            zsh
            # Structural search over TypeScript and Rust; the AI harness
            # prefers it to text search for code.
            ast-grep
          ];

          nodeTools = with pkgs; [
            nodejs_24
            pnpm
            typescript-language-server
            svelte-language-server
            tailwindcss-language-server
            vtsls
          ];

          # macOS builds against the system WKWebView: pkg-config is enough.
          # Linux renders through WebKitGTK 4.1 and needs the GTK stack,
          # libsoup for the webview's networking and glib-networking for TLS.
          webviewTools = [
            pkgs.pkg-config
          ]
          ++ lib.optionals stdenv.hostPlatform.isLinux (
            with pkgs;
            [
              gtk3
              webkitgtk_4_1
              libsoup_3
              glib
              glib-networking
              cairo
              pango
              gdk-pixbuf
              atk
              harfbuzz
              librsvg
              openssl
              fontconfig
            ]
          );

          webviewEnv = lib.optionalAttrs stdenv.hostPlatform.isLinux {
            # TLS for the webview, and the GSettings schemas GTK file dialogs need.
            GIO_MODULE_DIR = "${pkgs.glib-networking}/lib/gio/modules/";
            XDG_DATA_DIRS = lib.concatStringsSep ":" [
              "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}"
              "${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}"
            ];
            # WebKitGTK's DMA-BUF renderer shows blank windows on several GPU /
            # driver combinations (notably NVIDIA). Off by default in dev.
            WEBKIT_DISABLE_DMABUF_RENDERER = "1";
          };

          # `run` launches the app in dev through the project's `just run`. A
          # wrapper on PATH rather than a shellHook alias: direnv exports
          # variables, not aliases, and the hook runs in bash before exec'ing
          # zsh. Not named `r`, which is a zsh builtin and would shadow it.
          shorthands = [
            (pkgs.writeShellScriptBin "run" ''
              exec just run "$@"
            '')
          ];

          # ── Formatting ───────────────────────────────────────────────────
          # Canonical Prettier rules, formatting only and without plugins so
          # they cannot break a project that lacks one. Linked to the project
          # root on shell entry, where Prettier and its LSP discover it; a
          # project that needs plugins (prettier-plugin-svelte) commits its
          # own .prettierrc.json, which is never overwritten.
          prettierConfig = pkgs.writeText "prettierrc.json" (
            builtins.toJSON {
              useTabs = false;
              tabWidth = 4;
              printWidth = 100;
              singleQuote = true;
            }
          );

          # ── AI agent harness ─────────────────────────────────────────────
          # Copies every file under ./harness into the project root unless a
          # file already sits at that path, so a project's own edits always
          # win and a fresh project starts with the rules, MCP servers,
          # permissions, hooks, agents and commands. `@name@` and
          # `@description@` are filled from the shell name and package.json.
          bootstrapHarness = pkgs.writeShellApplication {
            name = "bootstrap-ai-harness";
            runtimeInputs = with pkgs; [
              coreutils
              findutils
              gnused
              jq
              git
            ];
            text = ''
              # Usage: bootstrap-ai-harness <name> [excluded relative path…]
              name="$1"
              shift
              root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
              description=""
              if [ -f "$root/package.json" ]; then
                description="$(jq -r '.description // empty' "$root/package.json")"
              fi

              created=()
              while IFS= read -r -d "" source; do
                relative="''${source#${./harness}/}"
                for excluded in "$@"; do
                  [ "$relative" = "$excluded" ] && continue 2
                done
                target="$root/$relative"
                [ -e "$target" ] && continue
                mkdir -p "$(dirname "$target")"
                sed -e "s|@name@|$name|g" -e "s|@description@|$description|g" "$source" > "$target"
                chmod 0644 "$target"
                created+=("$relative")
              done < <(find ${./harness} -type f -print0 | sort -z)

              if [ "''${#created[@]}" -gt 0 ]; then
                echo "tauri-projects · AI harness: created ''${created[*]} — review and commit"
              fi
            '';
          };

          # ── Dev shell ────────────────────────────────────────────────────
          mkTauriShell =
            {
              name,
              # Native deps and per-project extras (duckdb, cmake…)
              extra ? [ ],
              env ? { },
              hook ? "",
              # Copy the AI harness into the project on shell entry when its
              # files are missing.
              aiHarness ? true,
              # Harness paths (relative to the project root, e.g.
              # ".claude/commands/implement-issue.md") never to create, for a
              # project that removed one on purpose.
              aiHarnessExclude ? [ ],
              # Materialize the cross-target toolchain file at the project
              # root so rustup sees the same pin as Nix. Never clobbers a real
              # file.
              materializeToolchain ? true,
              # Link the shared Prettier config at the project root unless
              # the project committed its own.
              materializePrettierConfig ? true,
              # Re-exec interactive shells into zsh.
              zsh ? true,
            }:
            rust.mkRustShell {
              inherit name toolchain;
              materializeToolchain = false;
              extra = commonTools ++ nodeTools ++ webviewTools ++ shorthands ++ [ bootstrapHarness ] ++ extra;
              env = webviewEnv // env;
              hook = ''
                ${lib.optionalString materializeToolchain ''
                  if [ ! -e "$root/rust-toolchain.toml" ] || [ -L "$root/rust-toolchain.toml" ]; then
                    ln -sfn ${toolchainFile} "$root/rust-toolchain.toml"
                  fi
                ''}
                ${lib.optionalString materializePrettierConfig ''
                  if [ ! -e "$root/.prettierrc.json" ] || [ -L "$root/.prettierrc.json" ]; then
                    ln -sfn ${prettierConfig} "$root/.prettierrc.json"
                  fi
                ''}
                ${lib.optionalString aiHarness ''
                  bootstrap-ai-harness ${lib.escapeShellArgs ([ name ] ++ aiHarnessExclude)}
                ''}
                ${hook}
                ${lib.optionalString zsh ''
                  export SHELL=${pkgs.zsh}/bin/zsh
                  if [[ $- == *i* && -z "''${IN_TAURI_PROJECTS_ZSH:-}" ]]; then
                    export IN_TAURI_PROJECTS_ZSH=1
                    exec ${pkgs.zsh}/bin/zsh
                  fi
                ''}
              '';
            };

          # ── One-call project ─────────────────────────────────────────────
          # No package or checks: a Tauri bundle needs the frontend build and
          # platform signing, which belong to the project's own release flow.
          mkTauriProject = arguments: {
            devShells.default = mkTauriShell arguments;
            formatter = pkgs.nixfmt;
          };
        in
        {
          lib = {
            inherit
              pkgs
              toolchain
              toolchainFile
              prettierConfig
              crossTargets
              commonTools
              nodeTools
              webviewTools
              webviewEnv
              shorthands
              bootstrapHarness
              mkTauriShell
              mkTauriProject
              ;
            # rust-projects' pieces, for hand-rolled shells.
            rust = rust;
          };

          devShells.default = pkgs.mkShell {
            name = "tauri-projects";
            packages = rust.formatTools ++ rust.lspTools;
            shellHook = ''
              echo "tauri-projects · lib API: mkTauriProject · mkTauriShell · bootstrapHarness"
            '';
          };

          formatter = pkgs.nixfmt;
        }
      ) rust-projects.lib;
    in
    {
      lib = builtins.mapAttrs (_system: outputs: outputs.lib) perSystem;
      devShells = builtins.mapAttrs (_system: outputs: outputs.devShells) perSystem;
      formatter = builtins.mapAttrs (_system: outputs: outputs.formatter) perSystem;

      # ── Consumer entry point ─────────────────────────────────────────────
      # Applies `function` to this flake's per-system lib and transposes the
      # result into flake output shape, so a consumer needs exactly one input:
      #
      #   outputs = { tauri-projects, ... }:
      #     tauri-projects.forEachSystem (lib: lib.mkTauriProject { name = "…"; });
      forEachSystem =
        function:
        let
          results = builtins.mapAttrs (_system: outputs: function outputs.lib) perSystem;
          classes = rust-projects.inputs.nixpkgs.lib.unique (
            builtins.concatMap builtins.attrNames (builtins.attrValues results)
          );
        in
        builtins.listToAttrs (
          map (class: {
            name = class;
            value = builtins.mapAttrs (_system: result: result.${class}) (
              rust-projects.inputs.nixpkgs.lib.filterAttrs (_system: result: result ? ${class}) results
            );
          }) classes
        );

      templates.tauri = {
        path = ./templates/tauri;
        description = "Tauri project on the shared toolchain, webview stack and AI harness";
      };
      templates.default = self.templates.tauri;
    };
}
