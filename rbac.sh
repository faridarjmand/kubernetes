#!/bin/bash
read -p "Enter your username: " USERNAME
read -p "Enter your namespace: " NAMESPACE
if [ -z $USERNAME ] || [ -z $NAMESPACE ];then
        echo "pls complete the answer !!"
        exit
fi

mkdir $USERNAME 2>/dev/null
cd $USERNAME
openssl genrsa -out $USERNAME.pem
openssl req -new -key $USERNAME.pem -out $USERNAME.csr -subj "/CN=$USERNAME/O=backend-groupe"

BASE=$(cat $USERNAME.csr | base64 | tr -d '\n')

echo -e """
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: user-request-$USERNAME
spec:
  groups:
  - system:authenticated
  request: $BASE
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 315569260
  usages:
  - digital signature
  - key encipherment
  - client auth
""" > $USERNAME-csr.yaml

kubectl create -f $USERNAME-csr.yaml
kubectl certificate approve user-request-$USERNAME
kubectl get csr
kubectl get csr user-request-$USERNAME -o jsonpath='{.status.certificate}' | base64 -d > $USERNAME-user.crt

kubectl --kubeconfig ~/.kube/config-$USERNAME config set-cluster default --insecure-skip-tls-verify=true --server=https://10.17.17.200:6443
kubectl --kubeconfig ~/.kube/config-$USERNAME config set-credentials $USERNAME --client-certificate=$USERNAME-user.crt --client-key=$USERNAME.pem --embed-certs=true
kubectl --kubeconfig ~/.kube/config-$USERNAME config set-context default --cluster=default --user=$USERNAME --namespace=prod-drdr
kubectl --kubeconfig ~/.kube/config-$USERNAME config use-context default

echo -e """
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: $USERNAME
  namespace: $NAMESPACE
rules:
  - apiGroups: [\"\"]
    resources: [\"pods\", \"pods/log\", \"pods/exec\"]
    verbs: [\"get\", \"list\", \"watch\", \"log\", \"create\", \"update\", \"delete\"]
  - apiGroups: [\"apps\"]
    resources: [\"deployments\"]
    verbs: [\"get\", \"list\", \"update\", \"patch\"]
  - apiGroups: [\"\"]
    resources: [\"services\"]
    verbs: [\"get\", \"list\"]
  - apiGroups: [\"networking.k8s.io\"]
    resources: [\"ingresses\"]
    verbs: [\"get\", \"list\"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: $USERNAME
  namespace: $NAMESPACE
subjects:
- kind: User
  name: $USERNAME
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: $USERNAME
  apiGroup: rbac.authorization.k8s.io
""" > $USERNAME-Role.yaml
kubectl apply -f $USERNAME-Role.yaml
