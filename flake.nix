{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, ... }@inputs: with inputs; let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    packages.${system}.get-revisions = pkgs.writeScriptBin "get-revisions" ''
      exec ${pkgs.ruby_3_0}/bin/ruby ${./get-revisions.rb}
    '';
    defaultPackage.${system} = self.packages.${system}.get-revisions;
  };
}
