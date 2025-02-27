{ nixpkgs ? fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-23.11"
, pkgs ? import nixpkgs { }
, stdenv ? pkgs.stdenv
, fetchurl ? pkgs.fetchurl
, fetchFromGitHub ? pkgs.fetchFromGitHub
}:
pkgs.mkShell rec {

  # Variables
  kcliPlanName = "k3s-cluster";
  portainerVersion = "ce2-19";
  argoWorkflowsVersion = "v3.5.7";
  kataContainersVersion = "3.5.0";

  ## Set this to true to install Kata Containers in the k3s cluster
  ## Kata will be installed by default in the master node
  ## If you want to direct the installation to another node, set $NODENAME, and do:
  ## kubectl label node $NODENAME katacontainers.io/kata-runtime=true
  installKataContainers = true;

  # BuildInputs
  nativeBuildInputs = with pkgs; [
    python3
    python311Packages.libvirt
    k3sup
    libvirt
    kubectl
    openssh
    minio-client
  ];

  # Derivations
 
  ## SSH keys to be injected into the machines
  vm-keys = stdenv.mkDerivation {
    name = "vm-keys";
    buildInputs = with pkgs; [
      openssh
    ];
    phases = [
      "installPhase"
    ];
    installPhase = ''
      mkdir -p $out
      ssh-keygen -f $out/id_rsa
    '';
  };

  ## Portainer yaml to be installed in the k3s cluster
  portainerNodePort = fetchurl {
    url = "https://downloads.portainer.io/${portainerVersion}/portainer.yaml";
    hash = "sha256-11wXW6a/II07n7BhxBfBXtoTgziLqq/N+e3Qiaq7lEk=";
  };

  ## Argo Workflows yaml to be installed in the k3s cluster
  argoWorkflows = fetchurl {
    url = "https://github.com/argoproj/argo-workflows/releases/download/${argoWorkflowsVersion}/quick-start-minimal.yaml";
    hash = "sha256-UVPgYw2d2piO3WbZpHJT/dWY9Z7xtnroW0gXxIZcJGs=";
  };

  ## Kata Containers to be installed in the k3s cluster
  kataContainers =  if installKataContainers then 
    fetchFromGitHub {
      owner = "kata-containers";
      repo = "kata-containers";
      rev = kataContainersVersion;
      sha256 = "sha256-5pIJpyeydOVA+GrbCvNqJsmK3zbtF/5iSJLI2C1wkLM=";
    } else null;
  
  ## Kata Containers yamls 
  applyKataContainersYaml = if installKataContainers then ''
    echo "Installing Kata Containers..."
    kubectl apply -f ${kataContainers}/tools/packaging/kata-deploy/kata-rbac/base/kata-rbac.yaml
    sleep 5
    kubectl apply -k ${kataContainers}/tools/packaging/kata-deploy/kata-deploy/overlays/k3s
    sleep 5
    kubectl apply -f  ${kataContainers}/tools/packaging/kata-deploy/runtimeclasses/kata-runtimeClasses.yaml
  '' else "";

  # Shell Hook Scripts

  ## Shell Hook Entry Script 
  shellHookEntryScript = pkgs.writeShellScript "shellHookEntryScript.sh" ''
    if [ ! -f utils/kcli_plan.yml ]; then
      echo "Error: kcli_plan.yml does not exist."
      echo "Please, create it before proceeding."
      echo "Read README.md for more instructions."
      exit 1
    fi

    mkdir -p ~/.kcli/
    cp -rT ${vm-keys}/ ~/.kcli/
    chmod 600 ~/.kcli/*
    
    echo "SSH keys created at ${vm-keys} and copied to ~/.kcli"
    
    echo "Creating a Python venv and installing requirements..."
    python3 -m venv env
    source env/bin/activate
    pip3 install -r ./utils/requirements.txt

    echo "Creating a kcli plan named '${kcliPlanName}'..."
    kcli create plan -f utils/kcli_plan.yml ${kcliPlanName}
      
    vms=$(kcli list plan -o name | awk '{print $2}' | tr "," " " | tr -d "'[]")
    kcli_info="kcli info vm -f name,ip -o json $vms"
    until echo "$($kcli_info)" | grep -q "ip"; do sleep 1; echo "Waiting for VMs to get an ip..."; done
    echo "$($kcli_info)" > utils/vms_info.json

    echo "kcli plan created and VMs are up"
      
    echo "Bootstrapping k3s..."
    sleep 5
    python3 utils/k3sup.py
      
    export KUBECONFIG=$PWD/kubeconfig
      
    echo "Installing Portainer ${portainerNodePort}"
    kubectl apply -n portainer -f ${portainerNodePort}

    echo "Installing Argo Workflows ${argoWorkflowsVersion}"
    kubectl create namespace argo
    sleep 10
    kubectl apply -n argo -f ${argoWorkflows}
    kubectl apply -f utils/argo/argo-nodeport.yaml
    kubectl apply -f utils/minio-nodeport.yaml
    
    kubectl create rolebinding default-admin --clusterrole=admin --serviceaccount=argo:default -n argo

    ${applyKataContainersYaml}

    kubectl create role jenkins --verb=list,update --resource=workflows.argoproj.io,workfloweventbindings.argoproj.io
    
    kubectl create sa jenkins -n argo
    
    kubectl create rolebinding jenkins --role=jenkins --serviceaccount=argo:jenkins --namespace=argo
    
    kubectl apply -f utils/argo/argo-rolebinding-secret-token.yaml
    
    until kubectl create namespace argo-events; do sleep 10; echo "Waiting for Argo events namespace to create"; done

    export ARGO_TOKEN="Bearer $(kubectl get secret $(kubectl get sa jenkins -n argo -o jsonpath='{.secrets[0].name}') -n argo -o jsonpath='{.data.token}' | base64 --decode)"
    kubectl create secret generic argo-token --from-literal=token=$ARGO_TOKEN -n argo-events
    
    kubectl apply -f utils/argo/argo-events.yaml
    kubectl apply -f utils/argo/argo-gitlab-access.yaml
    kubectl apply -f utils/argo/argo-eventbus.yaml

    # Install with a validating admission controller
    kubectl apply -f utils/argo/argo-events-webhook.yaml

    kubectl apply -n argo-events -f utils/argo/argo-eventbus-native.yaml
    kubectl apply -n argo-events -f utils/argo/argo-event-source.yaml

    kubectl apply -n argo-events -f utils/argo/argo-cluster-role.yaml
    kubectl apply -n argo-events -f utils/argo/argo-role-binding.yaml

    kubectl apply -n argo-events -f utils/argo/argo-sensor-rbac.yaml
    kubectl apply -n argo-events -f utils/argo/argo-workflow-rbac.yaml

    # webhook sensor
    kubectl apply -n argo-events -f utils/argo/argo-webhook-sensor.yaml

    # port forwarding
    kubectl -n argo-events port-forward $(kubectl -n argo-events get pod -l eventsource-name=gitlab -o name) 12000:12000 

    vm1=$(echo $vms | grep -o '^[^ ]*')
    vm1_ip=$(kcli info vm -f ip -o name $vm1 | grep -oP 'ip:\s*\K[\d.]+')

    echo "VM1 IP is set to: $vm1_ip"

    until curl -s http://$vm1_ip:30771 > /dev/null; do sleep 3; echo "Waiting for MinIO to start..."; done
    until curl -s http://$vm1_ip:30772 > /dev/null; do sleep 3; echo "Waiting for MinIO to start..."; done

    echo "Uploading test-app.trustops.nix to MinIO"
    mc alias set storage http://$vm1_ip:30771 admin password

    echo "Creating bucket 'pipelinebucket' if it doesn't exist"
    mc mb --ignore-existing storage/pipelinebucket
    mc ls storage/pipelinebucket

    mc cp examples/test-app.trustops.nix storage/pipelinebucket/test-app.trustops.nix

    echo "Listing files in bucket after upload:"
    mc ls storage/pipelinebucket

    echo -e "\n----------------------------------\n"
    echo "All ready! Test your cluster with:"
    echo "kubectl config use-context default"
    echo "kubectl get node -o wide"
    echo ""
    echo "Shortly, you can also access:" 
    echo "Portainer UI via https://$vm1_ip:30779"
    echo "Argo Workflows UI via https://$vm1_ip:30770"
    echo "Argo Token: $ARGO_TOKEN"
    echo "MinIO UI (default credentials are admin:password) via http://$vm1_ip:30772"
    echo "To restart Portainer, run:"
    echo "kubectl rollout restart deployment portainer -n portainer"
    echo "To kill the kcli plan, run:"
    echo "kcli delete plan k3s-cluster"
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
