# Steps to create virtual cluster

Create new kind cluster configured for nodeport:

```shell
kind create cluster --name vch1 --config kind-cluster.yaml 
```

Install postgres

```shell
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install mypsql bitnami/postgresql
```

Get password 

```shell
export POSTGRES_PASSWORD=$(kubectl get secret --namespace default mypsql-postgresql -o jsonpath="{.data.postgresql-password}" | base64 --decode)  
```

Create secret with certs (TBD - check if kubeadm could be used to create them)

```shell
./create-secret.sh
```

Install Kube API server and Kine

```shell
cat kube-apiserver.yaml | sed "s/POSTGRES_PASSWORD/$POSTGRES_PASSWORD/g" | kubectl apply -f -
```

Create the NodeaPort service

```shell
kubectl apply -f service.yaml
```

Now you may just access from the nodeport.