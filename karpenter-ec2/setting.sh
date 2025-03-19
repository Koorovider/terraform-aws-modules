#!/bin/bash

# 첫 번째 인자로 CLUSTER_NAME을 받음
if [ -z "$1" ]; then
	echo "Usage: $0 <CLUSTER_NAME>"
	exit 1
fi

export CLUSTER_NAME="$1"

# Terraform Output에서 해당 클러스터 정보 가져오기
KARPENTER_INFO_JSON=$(terraform output -json karpenter_info)

# 해당 클러스터의 정보 추출 (jq 사용 필요)
export CLUSTER_REGION=$(echo "$KARPENTER_INFO_JSON" | jq -r --arg name "$CLUSTER_NAME" '.[$name].cluster_region')
export CLUSTER_VERSION=$(echo "$KARPENTER_INFO_JSON" | jq -r --arg name "$CLUSTER_NAME" '.[$name].cluster_version')
export NODE_IAM_ROLE_ARN=$(echo "$KARPENTER_INFO_JSON" | jq -r --arg name "$CLUSTER_NAME" '.[$name].node_iam_role_arn // empty')
export QUEUE_NAME=$(echo "$KARPENTER_INFO_JSON" | jq -r --arg name "$CLUSTER_NAME" '.[$name].queue_name // empty')
export KARPENTER_VERSION=$(curl -sL "https://api.github.com/repos/aws/karpenter/releases/latest" | jq -r ".tag_name" | sed 's/^v//')
export KARPENTER_NAMESPACE=kube-system


# 설정된 환경 변수 출력
echo "Environment variables set:"
echo "CLUSTER_NAME=${CLUSTER_NAME}"
echo "CLUSTER_VERSION=${CLUSTER_VERSION}"
echo "NODE_IAM_ROLE_ARN=${NODE_IAM_ROLE_ARN}"
echo "QUEUE_NAME=${QUEUE_NAME}"

KARPENTER_TASK() {
aws eks update-kubeconfig --region $CLUSTER_REGION --name $CLUSTER_NAME
aws iam create-service-linked-role --aws-service-name spot.amazonaws.com || true

# IAM Identity Mapping이 존재하는지 확인
EXISTING_MAPPING=$(eksctl get iamidentitymapping --cluster "${CLUSTER_NAME}" | grep "${NODE_IAM_ROLE_ARN}")

if [ -z "$EXISTING_MAPPING" ]; then
  # 존재하지 않으면 추가
  echo "Creating IAM identity mapping for ${NODE_IAM_ROLE_ARN}..."
  eksctl create iamidentitymapping \
    --username system:node:{{EC2PrivateDNSName}} \
    --cluster "${CLUSTER_NAME}" \
    --arn "${NODE_IAM_ROLE_ARN}" \
    --group system:bootstrappers \
    --group system:nodes
else
  echo "IAM identity mapping for ${NODE_IAM_ROLE_ARN} already exists. Skipping creation."
fi

helm registry logout public.ecr.aws
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter --version "${KARPENTER_VERSION}" --namespace "${KARPENTER_NAMESPACE}" \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=${NODE_IAM_ROLE_ARN} \
  --set "settings.clusterName=${CLUSTER_NAME}" \
  --set "settings.interruptionQueue=${QUEUE_NAME}" \
  --set controller.resources.requests.cpu=1 \
  --set controller.resources.requests.memory=1Gi \
  --set controller.resources.limits.cpu=1 \
  --set controller.resources.limits.memory=1Gi \
  --wait
}


# 변수 확인 후 Karpenter 리소스를 생성할지 여부를 묻기
if [ -z "$NODE_IAM_ROLE_ARN" ] || [ -z "$QUEUE_NAME" ]; then
    	echo "Karpenter is not fully enabled for this cluster."
		exit 0
    else
    	read -p "Do you want to proceed with Karpenter resource creation? (y/n): " INPUT
    	if [[ "$INPUT" == "y" || "$INPUT" == "yes" ]]; then
    	    # Karpenter 리소스 생성 함수 호출
    	    KARPENTER_TASK
    	fi
fi