{
  description = "LHN dual-environment container setup tools";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        python = pkgs.python312;

        # Docker repro test using the captured environment tarball.
        # This builds a local Docker image that matches the real container
        # (from env-capture tar pulled from HDL transfer repo) and runs
        # setup-system.sh + setup-user.sh inside it to verify the dual-conda
        # (old /opt/conda for pyspark + new /tmp/miniconda + r_env for modern R+py)
        # plus kernel registration, reticulate, lhn clones, etc.
        dockerReproTest = let
          reproDir = "${self}/repro-from-capture-20260603-132151";
        in pkgs.writeShellScriptBin "docker-repro-test" ''
          set -euo pipefail

          if [ ! -d "${reproDir}" ]; then
            # Fallback when running from a checkout (not via nix run from store)
            if [ -d "$(pwd)/repro-from-capture-20260603-132151" ]; then
              reproDir="$(pwd)/repro-from-capture-20260603-132151"
            else
              echo "ERROR: repro-from-capture-20260603-132151 directory not found."
              echo "Run from the updatebionic checkout root, or ensure the repro dir (from test-from-capture) exists."
              exit 1
            fi
          fi

          echo "Using repro dir: $reproDir"
          cd "$reproDir"

          echo "Building Docker image that matches the captured env (Ubuntu 18.04 + old conda + spark)..."
          docker build -t lhn-repro-env-capture-20260603-132151 -f Dockerfile .

          echo ""
          echo "Running test container as testuser."
          echo "This executes the current setup-system.sh + setup-user.sh (from the mounted source)"
          echo "and runs full verification (kernels, r_env reticulate+plotnine, lhn clones, etc)."
          echo ""

          # Mount the updatebionic checkout (parent of repro dir) so live scripts are tested.
          # The unpacked capture tar contents are inside the repro dir.
          docker run --rm -it \
            -v "$(dirname "$reproDir"):/host-updatebionic:ro" \
            -v "$reproDir/env-capture-20260603-132151:/capture:ro" \
            --user testuser \
            lhn-repro-env-capture-20260603-132151 \
            bash /run-test-inside.sh
        '';

      in {
        devShells.default = pkgs.mkShell {
          name = "updatebionic";

          packages = [
            # Python (for diagnostics scripts and testing)
            python
            pkgs.uv

            # Shell script development
            pkgs.shellcheck
            pkgs.shfmt

            # Utilities
            pkgs.git
            pkgs.jq
            pkgs.curl
            pkgs.tmux
            pkgs.tree

            # Docker repro test (builds matching image from capture tar + runs/tests the setup sh)
            dockerReproTest
          ];

          shellHook = ''
            export USER=''${USER:-$(whoami)}
            export LANG=C.UTF-8
            export LC_ALL=C.UTF-8

            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "  LHN Dual Environment Setup Tools"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            echo "  Python:     $(python --version)"
            echo "  ShellCheck: $(shellcheck --version | head -2 | tail -1)"
            echo ""
            echo "  Scripts:"
            echo "    ./setup-lhn-dual-envs.sh    Main container setup"
            echo "    ./nix/setup-nix-env.sh      Nix-based alternative"
            echo ""
            echo "  Docker repro test (from captured env tar):"
            echo "    docker-repro-test         # Builds matching image + runs setup-system.sh + setup-user.sh inside"
            echo "                              # (verifies kernels, r_env, reticulate/plotnine, lhn clones)"
            echo "    # Equivalent to: nix run .#docker-repro-test"
            echo ""
            echo "  Lint shell scripts:"
            echo "    shellcheck *.sh scripts/*.sh"
            echo "    shfmt -d *.sh"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          '';
        };

        packages = {
          docker-repro-test = dockerReproTest;
        };

        apps = {
          docker-repro-test = {
            type = "app";
            program = "${dockerReproTest}/bin/docker-repro-test";
          };
        };
      });
}
