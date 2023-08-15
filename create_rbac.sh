#!/bin/bash
mkdir $1 2>/dev/null
cd $1
openssl genrsa -out $1.pem
openssl req -new -key $1.pem -out $1.csr -subj "/CN=$1/O=backend-groupe"

BASE=$(cat $1.csr | base64 | tr -d '\n')

echo -e """
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: user-request-$1
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
""" > $1-csr.yaml

kubectl create -f $1-csr.yaml
kubectl certificate approve user-request-$1
kubectl get csr
kubectl get csr user-request-$1 -o jsonpath='{.status.certificate}' | base64 -d > $1-user.crt

kubectl --kubeconfig ~/.kube/config-$1 config set-cluster default --insecure-skip-tls-verify=true --server=https://10.17.17.200:6443
kubectl --kubeconfig ~/.kube/config-$1 config set-credentials $1 --client-certificate=$1-user.crt --client-key=$1.pem --embed-certs=true
kubectl --kubeconfig ~/.kube/config-$1 config set-context default --cluster=default --user=$1 --namespace=prod-drdr
kubectl --kubeconfig ~/.kube/config-$1 config use-context default

echo -e """
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: $1
  namespace: prod-drdr
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
  name: $1
  namespace: prod-drdr
subjects:
- kind: User
  name: $1
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: $1
  apiGroup: rbac.authorization.k8s.io
""" > $1-Role.yaml
kubectl apply -f $1-Role.yaml
