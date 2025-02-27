{ nixpkgs ? fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-24.05"
, pkgs ? import nixpkgs { } }:

pkgs.mkShell rec {
  CI_SHELL = true;
  
  # Variables
  
  ## your git server host and source repository, e.g., from GitLab
  GIT_HOST = "";
  GIT_URL = "";
  ## comma separated list of allowed signers following the format: 
  ## <username>@<hostname> namespaces="<namespace1>,<namespace2>" <algorithm> <key> <username>@<hostname>
  ALLOWED_SIGNERS = ''''; 
  ## branch/tag/commit to build
  GIT_BRANCH = "main";
  ## path to the TEE private key
  PK_PATH = "/tmp/pk";
  ## your artifact registry
  ## currently, not supported but trivial to implement
  EXPORT_URL = "";

  # Entry Commands
  BUILD_COMMAND = "go build -o main";
  TEST_COMMAND = "go test > test";
  AUDIT_COMMAND = "go mod verify > audit";

  # Specify system dependencies here
  nativeBuildInputs = with pkgs; [
    go
    git
    openssl
    zip
  ];

  executeProductionShell = if CI_SHELL then ''
  ${authenticatePhaseScript};
  ${buildPhaseScript};
  ${testPhaseScript};
  ${auditPhaseScript};

  echo "For signature verification purposes:"
  cat ${PK_PATH}.pub
  zip repo/signatures.zip repo/signature.*
  '' else "";

  # Phases

  authenticatePhase = ''
    echo "Running Authenticate Phase"

    # Create SSH directory and add the GitLab host to known_hosts
    mkdir -p ~/.ssh
    ssh-keyscan ${GIT_HOST} >> ~/.ssh/known_hosts

    # Clone only the specified branch
    git clone --branch ${GIT_BRANCH} --single-branch ${GIT_URL} repo
    cd repo

    # This step is a placeholder. 
    # Should be replaced with proper Remote Attestation mechanisms that load a trusted key into the TEE.
    # See https://github.com/confidential-containers/confidential-containers/blob/main/guides/coco-dev.md#deploy-and-configure-tenant-side-coco-key-broker-system-cluster for more details.
    ssh-keygen -t ed25519 -C tee.user@${GIT_HOST} -N "" -f ${PK_PATH}

    # Get the latest commit hash on the branch
    LATEST_COMMIT=$(git rev-parse HEAD)
    echo "Latest commit hash: $LATEST_COMMIT"
    export LATEST_COMMIT

    # Set up allowed signers
    touch allowed_signers
    echo "${ALLOWED_SIGNERS}" > allowed_signers
    git config --local gpg.ssh.allowedSignersFile allowed_signers

    # Verify the commit
    if git verify-commit $LATEST_COMMIT; then
      echo "Commit $LATEST_COMMIT is signed and verified."
    else
      echo "Commit $LATEST_COMMIT is not signed or verification failed."
      exit 1
    fi

    echo "Authenticate Phase passed"
  '';

  buildPhase = ''
    echo "Running Build Phase"
    cd repo
    ${BUILD_COMMAND}
    if [ $? -eq 0 ]; then
        ssh-keygen -Y sign -f "${PK_PATH}" -n file - < main > signature.build.sig
        echo "Build Phase passed"
    else
        echo "Build Phase failed"
        exit 1
    fi
    '';

  testPhase = ''
    echo "Running Test Phase"
    cd repo
    ${TEST_COMMAND}
    if [ $? -eq 0 ]; then
        ssh-keygen -Y sign -f "${PK_PATH}" -n file - < test > signature.test.sig
        echo "Test Phase passed"
    else
        echo "Test Phase failed"
        exit 1
    fi
    '';

  auditPhase = ''
    echo "Running Audit Phase"
    cd repo
    ${AUDIT_COMMAND}
    if [ $? -eq 0 ]; then
        ssh-keygen -Y sign -f "${PK_PATH}" -n file - < audit > signature.audit.sig
        echo "Audit Phase passed"
    else
        echo "Audit Phase failed"
        exit 1
    fi
    '';

  authenticatePhaseScript = pkgs.writeShellScript "authenticatePhaseScript.sh" ''
    #!/bin/sh
    echo "Starting authenticate phase script"
    ${authenticatePhase}
  '';

  buildPhaseScript = pkgs.writeShellScript "buildPhaseScript.sh" ''
    #!/bin/sh
    echo "Starting build phase script"
    ${buildPhase}
  '';

  testPhaseScript = pkgs.writeShellScript "testPhaseScript.sh" ''
    #!/bin/sh
    echo "Starting test phase script"
    ${testPhase}
  '';

  auditPhaseScript = pkgs.writeShellScript "auditPhaseScript.sh" ''
    #!/bin/sh
    echo "Starting audit phase script"
    ${auditPhase}
  '';

  # Pipeline
  shellHook = ''
    echo "Executing shell hook"
    alias authenticate="${authenticatePhaseScript}"
    alias build="${buildPhaseScript}"
    alias test="${testPhaseScript}"
    alias audit="${auditPhaseScript}"
    ${executeProductionShell}
  '';
}
