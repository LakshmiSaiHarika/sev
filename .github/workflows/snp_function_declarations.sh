#!/bin/bash

verify_snp_host() {
if sudo dmesg | grep -i "SEV-SNP enabled" 2>&1 >/dev/null; then
  echo -e "SEV-SNP not enabled on the host. Please follow these steps to enable:\n\
  $(echo "${AMDSEV_URL}" | sed 's|\.git$||g')/tree/${AMDSEV_DEFAULT_BRANCH}#prepare-host"
  # return 1
fi
}

ssh_guest_command() {
    # local guest_name=snp-guest-sev-${{ github.event.inputs.pull_request_number }}
    local guest_name=snp-guest-sev-$2
    local GUEST_SSH_KEY_PATH="${HOME}/snp/launch/${guest_name}/${guest_name}-key"
    if [ ! -f "${GUEST_SSH_KEY_PATH}" ]; then
      echo "SSH key not present, cannot verify guest SNP enabled."
      exit 1
    fi
    command="$1"
    guest_port_in_use="$3"
    # ssh -p ${{ env.guest_port_in_use }} -i "${GUEST_SSH_KEY_PATH}" -o "StrictHostKeyChecking no" -o "PasswordAuthentication=no" -o ConnectTimeout=1 amd@localhost "${command}"
    ssh -p ${guest_port_in_use} -i "${GUEST_SSH_KEY_PATH}" -o "StrictHostKeyChecking no" -o "PasswordAuthentication=no" -o ConnectTimeout=1 amd@localhost "${command}"
  }

verify_snp_guest_msr(){
  # Install guest rdmsr package dependencies to insert guest msr module
  # $1=${{ github.event.inputs.pull_request_number }} guest_port_in_use="$2"
  ssh_guest_command "sudo dnf install -y msr-tools > /dev/null 2>&1" $1 $2> /dev/null 2>&1
  ssh_guest_command "sudo modprobe msr" $1 $2 > /dev/null 2>&1
  local guest_msr_read=$(ssh_guest_command "sudo rdmsr -p 0 0xc0010131"  $1 $2)
  guest_msr_read=$(echo "${guest_msr_read}" | tr -d '\r' | bc)

  # Map all the sev features in a single associative array for all guest SEV features
  declare -A actual_sev_snp_bit_status=(
    [SEV]=$(( ( guest_msr_read >> 0) & 1))
    [SEV-ES]=$(( (guest_msr_read >> 1) & 1))
    [SNP]=$(( (guest_msr_read >> 2) & 1))
  )

  local sev_snp_error=""
  for sev_snp_key in "${!actual_sev_snp_bit_status[@]}";
  do
      if [[ ${actual_sev_snp_bit_status[$sev_snp_key]} != 1 ]]; then
        # Capture the guest SEV/SNP bit value mismatch
        sev_snp_error+=$(echo "$sev_snp_key feature is not active on the guest.\n");
      fi
  done

  if [[ ! -z "${sev_snp_error}" ]]; then
    >&2 echo -e "ERROR: ${sev_snp_error}"
    return 1
  fi
 }
  
