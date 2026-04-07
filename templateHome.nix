{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  cfg = config.age-template;

  # Configuration for an individual template file
  fileConfig =
    with types;
    submodule (
      { config, ... }:
      {
        options = {
          name = mkOption {
            type = str;
            default = config._module.args.name;
            description = "Name of the template";
          };

          vars = mkOption {
            type = attrsOf path;
            description = ''
              Mapping of variable names to files, typical usage:

              `<var-name> = config.age.secrets.<age-secret-name>.path;`

              Names must start with a lowercase letter and be valid bash "names."
            '';
            default = { };
            example = literalExpression ''
              vars = {
                consulToken = config.age.secrets.nomad-consul-token.path;
                encrypt = config.age.secrets.nomad-encrypt.path;
              };
            '';
          };

          content = mkOption {
            type = str;
            description = ''
              Content of template.
              `$name` will be replaced with the content of file in `vars.name`
            '';
            default = "";
            example = literalExpression ''
              content = '''
                consul {
                  token = "$consulToken"
                }
                server {
                  encrypt = "$encrypt"
                }
              ''';
            '';
          };

          path = mkOption {
            type = str;
            description = "Path (with filename) to store generated output";
            default = "${cfg.directory}/${config.name}";
          };

          mode = mkOption {
            type = str;
            description = "Permissions mode for the output file";
            default = "0400";
          };
        };
      }
    );
in
{
  options.age-template = {
    directory = mkOption {
      type = types.path;
      description = "Default directory to create output files in";
      default = "${config.home.sessionVariables.XDG_RUNTIME_DIR}/agenix-template";
    };

    files = mkOption {
      type = types.attrsOf fileConfig;
      description = "Templates files to process";
      default = { };
    };
  };

  config =
    let
      inherit (lib) escapeShellArg mapAttrsToList;

      mkScript =
        name: entry:
        let
          templateName = "agenix-template-" + name;
          content = if hasSuffix "\n" entry.content then entry.content else entry.content + "\n";

          eDir = escapeShellArg (dirOf entry.path);
          eOutput = escapeShellArg entry.path;
          eInput = escapeShellArg (pkgs.writeText "${name}.in" content);

          # Only substitute configured variables, others will be ignored.
          allowedVars = escapeShellArg (
            builtins.concatStringsSep " " (map (s: "$" + s) (attrNames entry.vars))
          );

          setEnvScript = builtins.concatStringsSep "\n" (
            mapAttrsToList (var: source: ''export ${var}="$(< ${escapeShellArg source})"'') entry.vars
          );

          # Standalone script to prevent exported secrets leaking.
          activationScript = pkgs.writeShellScript templateName ''
            set -eo pipefail

            mkdir -p ${eDir}
            # only executed by current user
            chmod 700 ${eDir}

            ${setEnvScript}
            ${pkgs.gettext}/bin/envsubst \
              ${allowedVars} \
              < ${eInput} > ${eOutput}

            chmod ${escapeShellArg entry.mode} ${eOutput}
          '';
        in
        {
          name = templateName;
          # Ensure execution happens after agenix secrets are decrypted and the HM write boundary.
          value = config.lib.dag.entryAfter [ "agenix" "writeBoundary" ] ''
            $DRY_RUN_CMD ${activationScript}
          '';
        };
    in
    mkIf (cfg.files != { }) {
      # Create an output file during activation for each entry in files.
      home.activation = attrsets.mapAttrs' mkScript cfg.files;
    };
}
