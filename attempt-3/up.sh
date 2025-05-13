

# We are going to install cert manager, metallb and nginx ingress controller


# Configure helm repositories
helm repo add jetstack https://charts.jetstack.io || true
helm repo add bitnami https://charts.bitnami.com/bitnami || true
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx || true

helm repo update


# Install cert-manager
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true \
  --wait

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


# Install metallb
echo "📝 Installing metallb..."
helm upgrade --install metallb metallb/metallb \
    --create-namespace -n metallb-system

# wait 5 seconds for metallb to be ready
sleep 5


# Wait for metallb to be ready
echo "⏳ Waiting for metallb CRDs to be ready..."
kubectl wait --for=condition=Established \
    crd/ipaddresspools.metallb.io \
    crd/l2advertisements.metallb.io \
    --timeout=60s
echo "✅ Metallb CRDs are ready."

# Create metallb config
echo "📝 Creating metallb config..."
kubectl apply -f ./k8s/metallb-config.yaml



# Install nginx ingress controller

# wait a few seconds for metallb to be ready
echo "⏳ Waiting for metallb to be ready..."
while ! kubectl get pods -n metallb-system | grep -q 'metallb-controller'; do
  sleep 5
done
echo "✅ Metallb is ready."

echo "📝 Installing NGINX Ingress Controller..."
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx --wait --timeout 10m --namespace ingress-nginx --create-namespace --values - <<EOF
controller:
  ingressClassResource:
    default: true
  service:
    type: LoadBalancer
    loadBalancerIP: 192.168.4.31

EOF



echo "create simple ns, nginx deployment, service and ingress"

kubectl create ns simple


kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  namespace: simple
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: nginx
          ports:
            - containerPort: 80
EOF

# Create nginx service

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: nginx
  namespace: simple
spec:
  type: ClusterIP
  ports:
    - port: 80
      targetPort: 80
  selector:
    app: nginx
EOF


# Create nginx ingress
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx
  namespace: simple
  annotations:
    cert-manager.io/cluster-issuer: self-signed-issuer
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - nginx.kubesoar.dev
      secretName: nginx-tls
  rules:
    - host: nginx.kubesoar.dev
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: nginx
                port:
                  number: 80
EOF

