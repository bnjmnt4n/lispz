{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?rev=093268502280540a7f5bf1e2a6330a598ba3b7d0";
    flake-utils.url = "github:numtide/flake-utils?rev=5aed5285a952e0b949eb3ba02c12fa4fcfef535f";
    zig.url = "github:mitchellh/zig-overlay";
  };

  outputs = { self, nixpkgs, flake-utils, zig }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages."${system}";
      in {
       devShell = pkgs.mkShell {
          nativeBuildInputs = [
            zig.packages."${system}"."0.10.0"
          ];
        };
      });
}
