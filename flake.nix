{
  description = "SkiaSharp C API development environment for Scala Native";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-25.11-darwin";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        version = "2.88.8";

        # System-specific mapping for NuGet assets
        systemMap = {
          "x86_64-linux" = {
            pkgName = "SkiaSharp.NativeAssets.Linux";
            rid = "linux-x64";
            ext = "so";
          };
          "aarch64-linux" = {
            pkgName = "SkiaSharp.NativeAssets.Linux";
            rid = "linux-arm64";
            ext = "so";
          };
          "x86_64-darwin" = {
            pkgName = "SkiaSharp.NativeAssets.macOS";
            rid = "osx";  
            ext = "dylib";
          };
          "aarch64-darwin" = {
            pkgName = "SkiaSharp.NativeAssets.macOS";
            rid = "osx"; 
            ext = "dylib";
          };
        };

        map = systemMap.${system} or (throw "Unsupported system: ${system}");

        # Derivation for SkiaSharp C Assets
        skia-c-api = pkgs.stdenv.mkDerivation {
          pname = "skia-c-api";
          inherit version;

          # Fetch headers from the mono/skia fork (Milestone 88 for SkiaSharp 2.88.x)
          srcHeaders = pkgs.fetchFromGitHub {
            owner = "mono";
            repo = "skia";
            rev = "dev/skia-84";
            sha256 = "sha256-F82jHxuV2odcD1RrxbSGjmAj3PZ90gY5PemjGTDyjKA=";
          };

          # Fetch the NuGet package (.nupkg is a zip archive)
          srcNuget = pkgs.fetchurl {
            url = "https://www.nuget.org/api/v2/package/${map.pkgName}/${version}";
            sha256 = "sha256-CdcrzQHwCcmOCPtS8EGtwsKsgdljnH41sFytW7N9PmI=";
          };

          nativeBuildInputs = [ pkgs.unzip ];

          dontUnpack = true;

          installPhase = ''
            mkdir -p $out/include/c $out/lib
            
            # 1. Extract and copy C headers
            # fetchFromGitHub gives a directory, no need to unzip
            cp -r $srcHeaders/include/c/* $out/include/c
            
            # 2. Extract NuGet package and copy the compiled native library
            # Path structure in NuGet: runtimes/<RID>/native/libSkiaSharp.<EXT>
            mkdir -p nuget
            unzip $srcNuget -d nuget
            
            LIB_SRC="nuget/runtimes/${map.rid}/native/libSkiaSharp.${map.ext}"
            if [ -f "$LIB_SRC" ]; then
              cp "$LIB_SRC" $out/lib/
            else
              echo "Error: Could not find library at $LIB_SRC"
              # List available runtimes to help debugging if it fails
              echo "Available runtimes in package:"
              find nuget/runtimes -maxdepth 2
              exit 1
            fi
          '';

          dontStrip = true;
        };
      in
      {
        packages.default = skia-c-api;

        devShells.default = pkgs.mkShell {
          name = "skia-bindgen-shell";

          nativeBuildInputs = [ pkgs.unzip ];
          buildInputs = [ skia-c-api ];

          shellHook = ''
            # Export paths for sn-bindgen and build tools
            export C_INCLUDE_PATH="${skia-c-api}/include/c/''${C_INCLUDE_PATH:+:}$C_INCLUDE_PATH"
            export CPLUS_INCLUDE_PATH="${skia-c-api}/include/c/''${CPLUS_INCLUDE_PATH:+:}$CPLUS_INCLUDE_PATH"
            export LIBRARY_PATH="${skia-c-api}/lib''${LIBRARY_PATH:+:}$LIBRARY_PATH"

            # Set dynamic library paths based on platform
            if [[ "$OSTYPE" == "linux-gnu"* ]]; then
              export LD_LIBRARY_PATH="${skia-c-api}/lib''${LD_LIBRARY_PATH:+:}$LD_LIBRARY_PATH"
            elif [[ "$OSTYPE" == "darwin"* ]]; then
              export DYLD_LIBRARY_PATH="${skia-c-api}/lib''${DYLD_LIBRARY_PATH:+:}$DYLD_LIBRARY_PATH"
            fi

            echo "SkiaSharp C API environment loaded."
            echo "Headers: ${skia-c-api}/include/c/"
            echo "Library: ${skia-c-api}/lib"
          '';
        };
      }
    );
}
