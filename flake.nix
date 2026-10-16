{
  description = "A TOML library for Zig";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
    zig = {
      url = "github:mitchellh/zig-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    flake-compat,
    zig,
  }: let
    overlays = [
      (final: prev: {
        zigpkgs = zig.packages.${prev.stdenv.hostPlatform.system};
      })
    ];
    systems = builtins.attrNames zig.packages;
  in
    flake-utils.lib.eachSystem systems (
      system: let
        pkgs = import nixpkgs {inherit overlays system;};
      in {
        devShell = pkgs.mkShell {
          buildInputs = with pkgs; [
            zigpkgs."0.17.0"
            zls
            bashInteractive
            gdb
            lldb
          ];
        };
      }
    );
}
