{
  description = "Text templating for agenix secrets";

  outputs =
    { self, ... }:
    {
      nixosModules.age-template = ./template.nix;
      nixosModules.default = self.nixosModules.age-template;

      homeManagerModules.age-template = ./templateHome.nix;
      homeManagerModules.default = self.homeManagerModules.age-template;
    };
}
