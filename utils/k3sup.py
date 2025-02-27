import json

# Step 1: Read and parse the JSON file
vms = []
with open('./utils/vms_info.json', 'r') as file:
    vms = [ json.loads(l) for l in file.readlines() ]

# Extracting the IP address of VM1
ip_vm1 = vms[0]['ip']

# Step 2: Run the k3sup commands using the extracted IP addresses
# Note: You might need to adjust the paths to the k3sup binary if it's not in your PATH
import subprocess

# Install k3s on VM1
# Adding as master node
install_command = f"k3sup install --ssh-key ~/.kcli/id_rsa --ip {ip_vm1} --user ubuntu --k3s-extra-args '--cluster-init'"
subprocess.run(install_command.split(), check=True)

# Join other VMs to the cluster initiated by VM1
# Adding as worker nodes
for vm in vms[1:]:
    ip_vm = vm['ip']
    join_command = f"k3sup join --ssh-key ~/.kcli/id_rsa --ip {ip_vm} --user ubuntu --server-ip {ip_vm1} --server-user ubuntu"
    subprocess.run(join_command.split(), check=True)
