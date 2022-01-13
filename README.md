# kealm

Kubernetes at the Edge Application Lifecycle Management

# Prereqs
To run the virtual cluster creation script, you will need the following:

- docker
- kind
- kubectl
- helm
- [clusteradm](https://github.com/open-cluster-management-io/clusteradm)
- [kubeadm](#installing-kubeadm)
- jq
- go >= 1.16 (if installing on `macos`, for building `kubeadm` )


## Creating a virtual cluster

Run the following command:

```
deploy/create-instance.sh 
```

this will create a virtual cluster instance in a kind cluster. 

After the script completes, you will get a message similar to:

```shell
cluster manager has been started! To join clusters run the command (make sure to use the correct <cluster-name>:

clusteradm join --hub-token <token> --hub-apiserver <api-server-url> --cluster-name <cluster-name>
```

You may now check the status of the virtual cluster by checking the pods running in the `vks-system` namespace:

```shell
kubectl get pods -n vks-system

NAME                                                       READY   STATUS    RESTARTS   AGE
cluster-manager-extensions-54b758b6d5-qx86t                1/1     Running   0          3h24m
cluster-manager-placement-controller-b9b8b4f67-b6t5q       1/1     Running   0          3h24m
cluster-manager-registration-controller-6769f48c79-vwlqg   1/1     Running   0          3h24m
kube-apiserver-6b75c996d8-fh5zx                            2/2     Running   3          3h25m
kube-controller-manager-58b46767b8-4jskt                   1/1     Running   2          3h24m
mypsql-postgresql-0                                        1/1     Running   0          3h25m
```

you may now create a new kind cluster to register it with the cluster manager:

```shell
kind create cluster --name cluster1
```

once the cluster is ready, copy and paste the command you got at the end of the creation of the virtual cluster, 
make sure also to use "cluster1" for cluster-name:

```shell
clusteradm join --hub-token <token> --hub-apiserver <api-server-url> --cluster-name <cluster-name>
```

Once the OCM agents are installed and started, you should see a message similar to:

```shell
Waiting for the management components to become ready...
Please log onto the hub cluster and run the following command:

    clusteradm accept --clusters cluster1
```    

Open another terminal, cd to the project directory, and set `KUBECONFIG` to point to the virtual cluster:

```shell
export KUBECONFIG=.vks/admin.conf
```

You should see a certificate signing request pending:

```shell
kubectl get csr

NAME             AGE     SIGNERNAME                            REQUESTOR                                                         REQUESTEDDURATION   CONDITION
cluster1-2b8hp   4m20s   kubernetes.io/kube-apiserver-client   system:serviceaccount:open-cluster-management:cluster-bootstrap   <none>              Pending
```

Approve the CSR and accept the cluster join request:

```shell
clusteradm accept --clusters cluster1
```

Verify that the new cluster is joined and available:

```shell
kubectl get managedclusters

NAME       HUB ACCEPTED   MANAGED CLUSTER URLS          JOINED   AVAILABLE   AGE
cluster1   true           https://192.168.1.153:31433   True     True        4m43s
```

## Installing kubadm:

### Installing on linux
If you are running on linux, you may just download a binary release (note that since kubeadm is only used to generate
certificates, you do not need to install any of the other prereqs for kubedm)

```shell
DOWNLOAD_DIR=/usr/local/bin
sudo mkdir -p $DOWNLOAD_DIR
RELEASE="$(curl -sSL https://dl.k8s.io/release/stable.txt)"
ARCH="amd64"
cd $DOWNLOAD_DIR
sudo curl -L --remote-name-all https://storage.googleapis.com/kubernetes-release/release/${RELEASE}/bin/linux/${ARCH}/kubeadm
sudo chmod +x kubeadm
```

### Installing on macOS
Since there is no official distribution for macOS, you will need to build from source:

```shell
mkdir -p ${GOPATH}/src/k8s.io
cd ${GOPATH}/src/k8s.io
git clone https://github.com/kubernetes/kubernetes.git
cd kubernetes
git checkout tags/v1.22.5
KUBE_BUILD_PLATFORMS=darwin/amd64 build/run.sh make WHAT=cmd/kubeadm
sudo cp _output/dockerized/bin/darwin/amd64/kubeadm /usr/local/bin
```

