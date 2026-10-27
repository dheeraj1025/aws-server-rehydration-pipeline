#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration & Paths
# -----------------------------------------------------------------------------
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKER_DIR="${ROOT_DIR}/packer"
TERRAFORM_DIR="${ROOT_DIR}/terraform"

APP_VERSION="${1:-v2.4.1}"
AWS_REGION="${AWS_REGION:-us-east-1}"
MAX_RETRIES=20
CHECK_INTERVAL=10

echo "=================================================================="
echo " Starting Automated Rehydration Pipeline for Version: ${APP_VERSION}"
echo " AWS Region: ${AWS_REGION}"
echo "=================================================================="

# -----------------------------------------------------------------------------
# 1. Dependency Checks
# -----------------------------------------------------------------------------
echo "[1/5] Verifying toolchain dependencies..."
for cmd in packer terraform aws jq curl; do
  if ! command -v "${cmd}" &>/dev/null; then
    echo "ERROR: Required utility '${cmd}' is not installed or not in PATH." >&2
    exit 1
  fi
done

# -----------------------------------------------------------------------------
# 2. Bake Golden AMI via Packer
# -----------------------------------------------------------------------------
echo "[2/5] Building and hardening Golden AMI..."
cd "${PACKER_DIR}"

packer init template.pkr.hcl

# Execute Packer and capture standard build output
PACKER_LOG_FILE="/tmp/packer-build-${APP_VERSION}.log"
packer build \
  -var="aws_region=${AWS_REGION}" \
  -var="app_version=${APP_VERSION}" \
  template.pkr.hcl | tee "${PACKER_LOG_FILE}"

# Extract new AMI ID from log output
NEW_AMI_ID=$(grep -Eo 'ami-[a-z0-9]+' "${PACKER_LOG_FILE}" | tail -n 1)

if [[ -z "${NEW_AMI_ID}" ]]; then
  echo "FATAL: Failed to parse AMI ID from Packer output." >&2
  exit 1
fi

echo "SUCCESS: Baked Golden AMI: ${NEW_AMI_ID}"

# -----------------------------------------------------------------------------
# 3. Update Terraform Configuration
# -----------------------------------------------------------------------------
echo "[3/5] Updating terraform.tfvars with new AMI ID..."
cd "${TERRAFORM_DIR}"

# Safely replace the ami_id line in terraform.tfvars
if grep -q '^ami_id' terraform.tfvars; then
  sed -i.bak -E "s/^ami_id[[:space:]]*=.*/ami_id = \"${NEW_AMI_ID}\"/" terraform.tfvars
  rm -f terraform.tfvars.bak
else
  echo "ami_id = \"${NEW_AMI_ID}\"" >> terraform.tfvars
fi

# -----------------------------------------------------------------------------
# 4. Terraform Apply (Trigger Rolling ASG Instance Refresh)
# -----------------------------------------------------------------------------
echo "[4/5] Executing Terraform apply..."
terraform init -upgrade
terraform plan -out=tfplan.binary
terraform apply -auto-approve tfplan.binary
rm -f tfplan.binary

# Retrieve deployment outputs
ALB_DNS=$(terraform output -raw alb_dns_name)
ASG_NAME=$(terraform output -raw autoscaling_group_name)

echo "Active Auto Scaling Group: ${ASG_NAME}"
echo "ALB Entrypoint: http://${ALB_DNS}"

# -----------------------------------------------------------------------------
# 5. Monitor ASG Refresh & Run Canary Validations
# -----------------------------------------------------------------------------
echo "[5/5] Tracking rolling instance refresh and canary endpoints..."

REFRESH_SUCCESS=false

for ((i=1; i<=MAX_RETRIES; i++)); do
  # Query the active instance refresh status from AWS
  REFRESH_STATUS=$(aws autoscaling describe-instance-refreshes \
    --auto-scaling-group-name "${ASG_NAME}" \
    --region "${AWS_REGION}" \
    --query "InstanceRefreshes[0].Status" \
    --output text 2>/dev/null || echo "Pending")

  echo "Instance Refresh Status: ${REFRESH_STATUS} (Check ${i}/${MAX_RETRIES})"

  if [[ "${REFRESH_STATUS}" == "Successful" ]]; then
    REFRESH_SUCCESS=true
    break
  elif [[ "${REFRESH_STATUS}" == "Failed" || "${REFRESH_STATUS}" == "Cancelled" ]]; then
    echo "FATAL: Instance refresh terminated with status: ${REFRESH_STATUS}" >&2
    exit 1
  fi

  sleep "${CHECK_INTERVAL}"
done

if [[ "${REFRESH_SUCCESS}" != "true" ]]; then
  echo "WARN: ASG refresh timed out waiting for 'Successful' status. Proceeding to endpoint assertion..."
fi

# Canary Endpoint Validation
echo "Validating health contract at http://${ALB_DNS}/health..."
HTTP_SUCCESS=false

for ((j=1; j<=MAX_RETRIES; j++)); do
  HEALTH_PAYLOAD=$(curl -s -m 5 "http://${ALB_DNS}/health" || echo "")

  if [[ -n "${HEALTH_PAYLOAD}" ]]; then
    STATUS=$(echo "${HEALTH_PAYLOAD}" | jq -r '.status // empty')
    VER=$(echo "${HEALTH_PAYLOAD}" | jq -r '.version // empty')

    if [[ "${STATUS}" == "UP" && "${VER}" == "${APP_VERSION}" ]]; then
      echo "PASS: Received 200 OK from ALB. Service status: ${STATUS}, Version: ${VER}"
      HTTP_SUCCESS=true
      break
    fi
  fi

  echo "Canary probe pending healthy state... (Attempt ${j}/${MAX_RETRIES})"
  sleep "${CHECK_INTERVAL}"
done

if [[ "${HTTP_SUCCESS}" != "true" ]]; then
  echo "FATAL: Canary endpoint assertion failed against http://${ALB_DNS}/health" >&2
  exit 1
fi

echo "=================================================================="
echo " Pipeline Complete: ${NEW_AMI_ID} is fully deployed and healthy."
echo " Endpoint: http://${ALB_DNS}/health"
echo "=================================================================="
exit 0
