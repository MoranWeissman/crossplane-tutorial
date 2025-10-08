{ pkgs ? import <nixpkgs> {
    config = {
      allowUnfree = true;
    };
  }
}:

let
  # Override awscli2 to skip tests - much faster builds
  awscli2-fast = pkgs.awscli2.overridePythonAttrs (old: {
    doCheck = false;
    doInstallCheck = false;
  });
in

pkgs.mkShell {
  packages = with pkgs; [
    # AWS tools
    awscli2-fast
    
    # Kubernetes & Crossplane
    kubectl
    crossplane-cli
    kubernetes-helm
    kind
    
    # Utilities
    jq
    yq-go
    gum
    gh
    upbound
    teller
    git
  ];
}
