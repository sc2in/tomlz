{
  description = "A TOML library for Zig";

  inputs = {
    zig2nix.url = "github:Cloudef/zig2nix";
  };

  outputs = {
    self,
    zig2nix,
    ...
  }: let
    zigVersion = "0.17.0";
    version = self.shortRev or self.dirtyShortRev or "dev";
    flake-utils = zig2nix.inputs.flake-utils;
  in
    with builtins; (flake-utils.lib.eachDefaultSystem (system: let
      env = zig2nix.outputs.zig-env.${system} {
        zig = zig2nix.outputs.packages.${system}."zig-${(replaceStrings ["."] ["_"] zigVersion)}";
      };
      zonLock =
        if builtins.readFile ./build.zig.zon2json-lock == ""
        then throw "build.zig.zon2json-lock is empty — regenerate it with `update-zon` inside `nix develop` and commit the result"
        else ./build.zig.zon2json-lock;

      updateZon = pkgs.writeShellApplication {
        name = "update-zon";
        runtimeInputs = [pkgs.git pkgs.jq];
        meta.description = "Regenerate build.zig.zon2json-lock atomically, validating the result";
        text = ''
          cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
          if ! command -v zig &>/dev/null; then
            echo "zig is not installed or not in PATH" >&2
            exit 1
          fi
          echo "Regenerating build.zig.zon2json-lock..."
          # zon2lock truncates its destination before it starts
          # fetching, so writing straight to the real lock risks
          # leaving a 0-byte file behind on failure or ^C. Generate
          # into a temp file, validate, then move into place.
          tmp="$(mktemp .build.zig.zon2json-lock.XXXXXX)"
          trap 'rm -f "$tmp"' EXIT
          env -u ZIG_GLOBAL_CACHE_DIR zig2nix zon2lock build.zig.zon "$tmp"
          if ! jq -e 'type == "object"' "$tmp" >/dev/null 2>&1; then
            echo "error: generated lock is empty or invalid JSON; keeping existing build.zig.zon2json-lock" >&2
            exit 1
          fi
          mv -f "$tmp" build.zig.zon2json-lock
          echo "build.zig.zon2json-lock updated."
        '';
      };
    in
      with env.pkgs.lib; {
        packages = {
          default = tomlz;
          tomlz = env.package {
            pname = "tomlz";
            inherit version;
            zigBuildFlags = "-Doptimize=Safe";
            src = fileset.toSource {
              root = ./.;
              fileset = lib.fileset.unions [
                ./build.zig
                ./build.zig.zon
                ./build.zig.zon2json-lock
                ./src
                ./examples
                ./tests
              ];
            };
          };
        };
        devShells = let
          pkgs = env.pkgs;

          fuzz = pkgs.writeShellApplication {
            name = "fuzz";
            meta.description = "Run coverage-guided fuzz tests with the Zig web UI (optional port argument, default 8080)";
            text = ''
              PORT="''${1:-8080}"
              echo "▸ Starting fuzzer — web UI at http://127.0.0.1:$PORT"
              zig build test --fuzz --port "$PORT"
            '';
          };
        in {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [
              zigpkgs."0.17.0"
              zls
              bashInteractive
              gdb
              lldb
              fuzz
            ];
          };
        };
        apps = {
          sbom = let
            app = pkgs.writeShellApplication {
              name = "sbom";
              runtimeInputs = [pkgs.git pkgs.jq];
              text = ''
                cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
                exec bash tools/sbom.sh "$@"
              '';
            };
          in {
            type = "app";
            program = "${app}/bin/sbom";
            meta.description = "Generate a CycloneDX SBOM of compiled-in Zig dependencies";
          };
        };
        bump = let
          bump-app = pkgs.writeShellApplication {
            name = "bump";
            runtimeInputs = with pkgs; [coreutils gnused gawk git];
            meta.description = "Bump version in build.zig.zon and roll the CHANGELOG";
            text = ''
              dry=0
              commit=1
              arg=""
              for a in "$@"; do
                case "$a" in
                  --dry-run) dry=1 ;;
                  --no-commit) commit=0 ;;
                  -h | --help)
                    echo "usage: nix run .#bump -- <version|patch|minor|major> [--dry-run] [--no-commit]"
                    exit 0
                    ;;
                  *) arg="$a" ;;
                esac
              done

              if [ -z "$arg" ]; then
                echo "usage: nix run .#bump -- <version|patch|minor|major> [--dry-run] [--no-commit]" >&2
                exit 1
              fi

              cur=$(sed -nE 's/^[[:space:]]*\.version = "([^"]+)",/\1/p' build.zig.zon | head -n1)
              if [ -z "$cur" ]; then
                echo "error: could not read current version from build.zig.zon" >&2
                exit 1
              fi

              case "$arg" in
                major | minor | patch)
                  IFS=. read -r ma mi pa <<< "$cur"
                  case "$arg" in
                    major)
                      ma=$((ma + 1))
                      mi=0
                      pa=0
                      ;;
                    minor)
                      mi=$((mi + 1))
                      pa=0
                      ;;
                    patch) pa=$((pa + 1)) ;;
                  esac
                  new="$ma.$mi.$pa"
                  ;;
                *) new="$arg" ;;
              esac

              if ! [[ "$new" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                echo "error: invalid version '$new' (expected X.Y.Z or patch|minor|major)" >&2
                exit 1
              fi

              today=$(date +%F)
              echo "Release: $cur -> $new ($today)"

              if [ "$dry" = 1 ]; then
                echo "[dry-run] would update:"
                echo "  build.zig.zon  .version = \"$new\""
                echo "  CHANGELOG.md   roll [Unreleased] into [$new] - $today"
                exit 0
              fi

              echo "Relocking zon file..."
              ${getExe updateZon}/bin/update-zon
              echo "Relocked build.zig.zon2json-lock"

              sed -i -E "s/^([[:space:]]*\.version = )\"[^\"]+\",/\1\"$new\",/" build.zig.zon
              awk -v ver="$new" -v dt="$today" '
                !done && /^## \[Unreleased\]/ {
                  print "## [Unreleased]";
                  print "";
                  print "## [" ver "] - " dt;
                  done = 1;
                  next
                }
                { print }
              ' CHANGELOG.md > CHANGELOG.md.tmp && mv CHANGELOG.md.tmp CHANGELOG.md

              echo "Updated build.zig.zon, CHANGELOG.md"

              if [ "$commit" = 1 ]; then
                git add build.zig.zon CHANGELOG.md
                git commit -m "chore: release $new"
                echo ""
                echo "Committed 'chore: release $new'. Publish with:"
                echo "  git tag v$new && git push origin HEAD v$new"
              else
                echo ""
                echo "Files edited (not committed). Then:"
                echo "  git add build.zig.zon CHANGELOG.md && git commit -m 'chore: release $new'"
                echo "  git tag v$new && git push origin HEAD v$new"
              fi
            '';
          };
        in {
          type = "app";
          program = "${bump-app}/bin/bump";
          meta.description = "Bump version in build.zig.zon and roll the CHANGELOG for a release";
        };
      }));
}
