{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, ... }@inputs: with inputs; let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    defaultApp.${system} = { type = "app"; program = toString self.packages.${system}.get-revisions; };

    packages.${system}.get-revisions = pkgs.writers.writeBash "get-revisions" ''
      exec ${pkgs.ruby_3_0}/bin/ruby ./get-revisions.rb
    '';
  };
}
