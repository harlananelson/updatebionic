{
  description = "Reproducible R/Python data science environment for CHRWD pipeline";

  # Pin nixpkgs for reproducibility
  # Using nixos-24.05 which has R 4.4.x and good package coverage
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;  # Some packages may need this
          };
        };

        # R version from nixpkgs (4.4.x in 24.05)
        R = pkgs.R;

        # ============================================================
        # R Packages - mapped from requirements-R.txt and CRAN list
        # ============================================================
        # Note: Nix package names use underscores, not dots or hyphens
        # Some packages may need to be built from CRAN if not in nixpkgs
        
        rPackagesFromNixpkgs = with pkgs.rPackages; [
          # From requirements-R.txt (conda-forge equivalents)
          Matrix
          MASS
          tidyverse
          data_table
          tidymodels
          targets
          tarchetypes
          gtsummary
          ggpubr
          pacman
          pak
          renv
          here
          janitor
          curl
          survminer
          nanoparquet
          remotes
          ranger
          GGally
          xgboost
          pdp
          contrast
          estimability
          mvtnorm
          numDeriv
          emmeans
          pillar
          pkgconfig
          mgcv
          
          # From CRAN install list in script
          ggsurvfit
          themis
          vip
          IRkernel
          reticulate
          visNetwork
          config
          sparklyr
          table1
          tableone
          svglite
          
          # Additional dependencies that are commonly needed
          devtools
          knitr
          rmarkdown
          
          # For Jupyter integration
          repr
          pbdZMQ
          uuid
        ];

        # Packages that may not be in nixpkgs - build from CRAN
        # This is a fallback mechanism for missing packages
        buildRPackageFromCRAN = name: pkgs.rPackages.buildRPackage {
          name = name;
          src = pkgs.fetchurl {
            url = "https://cran.r-project.org/src/contrib/${name}_latest.tar.gz";
            # Note: In practice, you'd pin the version and hash
            # This is a template - actual usage requires specific versions
            sha256 = pkgs.lib.fakeSha256;
          };
        };

        # Packages to attempt from CRAN if not in nixpkgs
        # Uncomment and add hash if needed:
        # rPackagesFromCRAN = [
        #   (buildRPackageFromCRAN "Delta")
        #   (buildRPackageFromCRAN "equatiomatic")
        #   (buildRPackageFromCRAN "survRM2")
        #   (buildRPackageFromCRAN "cardx")
        # ];

        # ============================================================
        # Python environment
        # ============================================================
        pythonEnv = pkgs.python310.withPackages (ps: with ps; [
          # From requirements.txt
          patsy
          numpy
          scipy
          pandas
          plotnine
          lifelines
          geopandas
          duckdb
          polars
          
          # Jupyter integration
          jupyterlab
          ipykernel
          notebook
          
          # Additional useful packages
          pyarrow      # For parquet interop
          pyproj       # For geopandas
          
          # Note: jupyterlab-quarto is installed via Quarto, not pip in Nix
        ]);

        # ============================================================
        # R wrapped with packages
        # ============================================================
        rEnv = pkgs.rWrapper.override {
          packages = rPackagesFromNixpkgs;
        };

        # RStudio with packages (optional, comment out if not needed)
        # rstudioEnv = pkgs.rstudioWrapper.override {
        #   packages = rPackagesFromNixpkgs;
        # };

      in {
        # Development shell - the main entry point
        devShells.default = pkgs.mkShell {
          name = "chrwd-datascience";
          
          buildInputs = [
            # Core languages
            rEnv
            pythonEnv
            
            # Quarto (latest in nixpkgs)
            pkgs.quarto
            
            # System dependencies for R packages
            pkgs.gdal
            pkgs.geos
            pkgs.proj
            pkgs.udunits
            pkgs.freetype
            pkgs.libpng
            
            # Build tools
            pkgs.cmake
            pkgs.pkg-config
            
            # Utilities
            pkgs.vim
            pkgs.curl
            pkgs.git
            
            # For Jupyter
            pkgs.pandoc
          ];

          shellHook = ''
            echo "=========================================="
            echo "CHRWD Data Science Environment (Nix)"
            echo "=========================================="
            echo ""
            echo "R version: $(R --version | head -n1)"
            echo "Python version: $(python --version)"
            echo "Quarto version: $(quarto --version)"
            echo ""
            
            # Set R library path
            export R_LIBS_USER="$PWD/.nix-R-library"
            mkdir -p "$R_LIBS_USER"
            
            # Configure reticulate to use this Python
            export RETICULATE_PYTHON="${pythonEnv}/bin/python"
            
            # Register Jupyter kernels if not already done
            if [[ ! -d "$HOME/.local/share/jupyter/kernels/r_nix" ]]; then
              echo "Registering R kernel for Jupyter..."
              R -e "IRkernel::installspec(name = 'r_nix', displayname = 'R (Nix)')" 2>/dev/null || true
            fi
            
            if [[ ! -d "$HOME/.local/share/jupyter/kernels/python_nix" ]]; then
              echo "Registering Python kernel for Jupyter..."
              python -m ipykernel install --user --name "python_nix" --display-name "Python 3.10 (Nix)" 2>/dev/null || true
            fi
            
            echo ""
            echo "Available commands:"
            echo "  R          - Start R console"
            echo "  python     - Start Python console"
            echo "  quarto     - Quarto CLI"
            echo "  jupyter lab - Start JupyterLab"
            echo ""
            echo "For targets pipeline: R -e \"targets::tar_make()\""
            echo "=========================================="
          '';

          # Environment variables
          LOCALE_ARCHIVE = "${pkgs.glibcLocales}/lib/locale/locale-archive";
        };

        # Export packages for inspection
        packages.default = rEnv;
      }
    );
}
