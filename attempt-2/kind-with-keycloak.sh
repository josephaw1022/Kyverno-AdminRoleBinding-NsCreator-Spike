#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="keycloak-lab"
CUSTOM_DOMAIN="keycloak.localhost"

cat <<EOF | kind create cluster --name "$CLUSTER_NAME" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
            enforce-node-allocatable: ""
    extraPortMappings:
      - containerPort: 30080
        hostPort: 80
        protocol: TCP
      - containerPort: 30443
        hostPort: 443
        protocol: TCP

  - role: worker
  - role: worker
  - role: worker
EOF


helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add jetstack https://charts.jetstack.io
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update


echo "📝 Installing NGINX Ingress Controller..."
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx --wait --timeout 10m \
  --namespace ingress-nginx --create-namespace --values - <<EOF
controller:
  service:
    type: NodePort
    nodePorts:
      http: 30080
      https: 30443
  ingressClassResource:
    default: true
  ingressClass: nginx
EOF

echo "📝 Installing cert-manager..."
helm upgrade --install cert-manager jetstack/cert-manager --wait --timeout 10m \
  --namespace cert-manager --create-namespace --values - <<EOF
crds:
  enabled: true
EOF

# wait for crd to be ready
echo "⏳ Waiting for cert-manager CRDs to be ready..."
while ! kubectl get crd | grep -q 'cert-manager.io'; do
  sleep 5
done
echo "✅ Cert-manager CRDs are ready."



echo "📝 Creating self-signed ClusterIssuer..."
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: self-signed-issuer
spec:
  selfSigned: {}
EOF


echo "📝 Installing NGINX Ingress Controller..."
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx --wait --timeout 10m --namespace ingress-nginx --create-namespace --values - <<EOF
controller:
  service:
    type: NodePort
    nodePorts:
      http: 30080
      https: 30443
  ingressClassResource:
    default: true
  ingressClass: nginx
EOF



helm upgrade --install keycloak bitnami/keycloak --version 24.4.11 --wait --timeout 15m \
  --namespace keycloak --create-namespace --values - <<EOF

auth:
  createAdminUser: true
  adminUser: admin
  adminPassword: admin
  managementUser: manager
  managementPassword: manager

ingress:
  ingressClassName: nginx
  enabled: true
  hostnameStrict: false
  hostname: keycloak.localhost
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: self-signed-issuer
  tls: true
  secretName: keycloak-tls-secret


proxyHeaders: "xforwarded"

proxy: edge

networkPolicy:
  enabled: false

httpRelativePath: "/"


postgresql:
  enabled: true
  auth:
    postgresPassword: "JoeMontana11#"
    username: keycloak
    password: "JoeMontana11#"
    database: keycloak
  architecture: standalone

EOF