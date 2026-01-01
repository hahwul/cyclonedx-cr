{
  description = "CycloneDX SBOM generator for Crystal shard files";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        cyclonedx-cr = pkgs.crystal.buildCrystalPackage rec {
          pname = "cyclonedx-cr";
          version = "1.0.2";

          src = ./.;

          shardsFile = ./shards.nix;

          crystalBinaries.cyclonedx-cr.src = "src/main.cr";

          crystalBinaries.cyclonedx-cr.options = [ "--release" "--no-debug" ];

          nativeBuildInputs = [ pkgs.crystal pkgs.shards ];
          buildInputs = [ ];

          buildPhase = ''
            runHook preBuild
            shards build --release
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin
            cp bin/cyclonedx-cr $out/bin/cyclonedx-cr
            runHook postInstall
          '';

          doCheck = false;

          meta = with pkgs.lib; {
            description = "CycloneDX SBOM generator for Crystal shard files";
            homepage = "https://github.com/hahwul/cyclonedx-cr";
            license = licenses.mit;
            maintainers = [ "hahwul" ];
            mainProgram = "cyclonedx-cr";
          };
        };
      in
      {
        packages.default = cyclonedx-cr;

        devShells.default = pkgs.mkShell {
          inputsFrom = [ cyclonedx-cr ];
          nativeBuildInputs = with pkgs; [ crystal shards crystal2nix ];
          shellHook = ''
            echo "cyclonedx-cr development environment loaded (via Nix)"
            echo "Running shards install..."
            shards install || true
          '';
        };
      });
}
