# Trustworthy CI Pipelines Demonstrator

This repository contains source code used to demonstrate the implementation of the Trustworthy CI pipelines architecture detailed in the paper:

1. First, it sets up a multi-node Kubernetes cluster, using [k3s](https://github.com/k3s-io/k3s), and installs [Argo Workflows](https://github.com/argoproj/argo-workflows) and [Portainer](https://github.com/portainer/portainer). It also installs and enables the [Kata Containers + Confidential Containers](https://github.com/confidential-containers/confidential-containers) runtimes for the TEE VMs (e.g. `kata-qemu-tdx`). If your system does not have TEE capabilities, you can fall back to a non-TEE Kata VM runtime (e.g. `kata-qemu`). This is a placeholder demonstrator, while technology like Confidential Containers (built upon the Kata runtime) keep maturing. The missing capabilities are: memory encryption, attestation, and other TEE features. Similarly, automated key management capabilities are also missing, but can be integrated following the [documentation](https://github.com/confidential-containers/confidential-containers/blob/main/guides/coco-dev.md#deploy-and-configure-tenant-side-coco-key-broker-system-cluster). In this demo, we skip these broader integrations and simulate their use.
2. In the `examples` folder, you can find workflow examples that can be imported into Argo Workflows. Argo is also configured to listen to webhooks from GitLab, to trigger CI pipelines upon specific events in the repository. Follow the instructions in the [GitLab documentation](https://docs.gitlab.com/ee/user/project/integrations/webhooks.html) and [Argo Workflows documentation](https://argo-workflows.readthedocs.io/en/latest/webhooks/) to configure it. It is not a crucial part of the demonstrator, because the repository used can be cloned from anywhere and triggered manually.
3. The source repository should, however, contain commit signatures and the public keys of the authorized signers should be captured. In `examples/test-app.trustops.nix`, you can find an example of the commit signature verification.

To run the demonstrator, you need [Nix](https://nixos.org/download/).

## Setting up the k3s cluster:

VM k3s hosts are orchestrated using [kcli](https://kcli.readthedocs.io/en/latest/).

First, under the `utils` folder, create a file named `kcli_plan.yml`. The template file `template.kcli_plan.yml` contains template configurations that can be copied:

```sh
cp utils/template.kcli_plan.yml utils/kcli_plan.yml 
```

Then, if Nix is installed in your system, do:

```bash
# Install the k3s cluster
nix-shell install.nix
```

This will create a kcli plan named `k3s-cluster`, deploying the VMs, and bootstrapping a k3s cluster. To modify the configuration, edit `kcli_plan.yml` and/or `k3sup.py` before running `install.nix`.

Follow the command line instructions to access the UIs of Argo Workflows, Portainer, and MinIO.

> Note: To delete the plan, run 
> `kcli delete plan k3s-cluster` 

If you exit the Nix shell, you can reconnect without having to install the k3s cluster again:

```bash
# Connect back to kcli
nix-shell connect.nix
```

## Examples:

The folder [examples](examples/) contains some workflow examples to be imported into Argo Workflows.
