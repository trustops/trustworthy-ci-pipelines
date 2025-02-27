{ nixpkgs ? fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-23.11"
, pkgs ? import nixpkgs { }
, stdenv ? pkgs.stdenv
}:
pkgs.mkShell rec {

  # Variables
  kcliPlanName = "k3s-cluster";

  # BuildInputs
  nativeBuildInputs = with pkgs; [
    python3
    python311Packages.libvirt
    libvirt
    kubectl
    openssh
    minio-client
  ];

  # Shell Hook Scripts

  ## Shell Hook Entry Script 
  shellHookEntryScript = pkgs.writeShellScript "shellHookEntryScript.sh" ''
    echo "Creating a Python venv and installing requirements..."
    python3 -m venv env
    source env/bin/activate
    pip3 install -r ./utils/requirements.txt

    export KUBECONFIG=$PWD/kubeconfig
      
    vms=$(kcli list plan -o name | awk '{print $2}' | tr "," " " | tr -d "'[]")
    vm1=$(echo $vms | grep -o '^[^ ]*')
    vm1_ip=$(kcli info vm -f ip -o name $vm1 | grep -oP 'ip:\s*\K[\d.]+')

    echo -e "\n----------------------------------\n"
    echo "All ready! Test your cluster with:"
    echo "kubectl config use-context default"
    echo "kubectl get node -o wide"
    echo ""
    echo "You can also access:"
    echo "Portainer UI via https://$vm1_ip:30779"
    echo "Argo Workflows UI via https://$vm1_ip:30770"
    echo "MinIO UI via http://$vm1_ip:30772"
    echo "To restart Portainer, run:"
    echo "kubectl rollout restart deployment portainer -n portainer"
  '';

  ## Shell Hook Exit Script 
  shellHookExitScript = pkgs.writeShellScript "shellHookExitScript.sh" ''
    echo "Exiting..."
    echo "To delete the cluster, run:"
    echo "nix-shell connect.nix"
    echo "kcli delete plan ${kcliPlanName} -y"
  '';

  # Shell Hooks
  shellHook = ''
    source ${shellHookEntryScript}
    trap ${shellHookExitScript} EXIT
  '';
}
