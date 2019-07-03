#!/bin/bash -xe
export KOPS_STATE_STORE=s3://$S3_BUCKET
export KOPS_CLUSTER_NAME=$CLUSTER_NAME


aws s3 ls
env
[ -r "/kops/$KOPS_CLUSTER_NAME/.ssh" ] || mkdir -p /kops/$KOPS_CLUSTER_NAME/.ssh
[ -r "/kops/$KOPS_CLUSTER_NAME/.kube" ] || mkdir -p /kops/$KOPS_CLUSTER_NAME/.kube

#There is a bug with ktmpl. It does not replace variable in a key name.
cat cluster-template.yaml | envsubst | \
  ktmpl -p CLUSTER_NAME $KOPS_CLUSTER_NAME \
        -p S3_BUCKET $S3_BUCKET \
        -p AZ_1 $AZ_1 \
        -p AZ_2 $AZ_2 \
        -p AZ_3 $AZ_3 - | HOME=/kops/$KOPS_CLUSTER_NAME kops replace -f - --force

#Creating ssh key to be able access aws nodes. ssh -i /kops/dev.optimeas.net/.ssh/id_rsa admin@ec2-54-93-186-127.eu-central-1.compute.amazonaws.com
[ -r "/kops/$KOPS_CLUSTER_NAME/.ssh/id_rsa" ] || {
  ssh-keygen -f /kops/$KOPS_CLUSTER_NAME/.ssh/id_rsa -N '' -q -t rsa
  kops create secret --name $KOPS_CLUSTER_NAME sshpublickey admin -i /kops/$KOPS_CLUSTER_NAME/.ssh/id_rsa.pub
}

cat ig-template.yaml | envsubst | \
  ktmpl -p CLUSTER_NAME $KOPS_CLUSTER_NAME \
        -p AZ_1 $AZ_1 \
        -p AZ_2 $AZ_2 \
        -p AZ_3 $AZ_3 - | HOME=/kops/$KOPS_CLUSTER_NAME kops replace -f - --force

HOME=/kops/$KOPS_CLUSTER_NAME kops update cluster  --yes
set +e
HOME=/kops/$KOPS_CLUSTER_NAME kops rolling-update cluster --yes
set -e

# Waiting for cluster
while :; do
  echo "Waiting for the cluster"
  set +e
  HOME=/kops/$KOPS_CLUSTER_NAME/ kops validate cluster && break
  set -e
  sleep 5
done

#Install addons
for file in `ls addons`; do
  cat addons/$file | envsubst | HOME=/kops/$KOPS_CLUSTER_NAME kubectl apply -f -
done
