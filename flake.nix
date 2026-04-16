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
            echo "  Lint shell scripts:"
            echo "    shellcheck *.sh scripts/*.sh"
            echo "    shfmt -d *.sh"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          '';
        };
      });
}
