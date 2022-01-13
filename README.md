# kealm

Kubernetes at the Edge Application Lifecycle Management. 

At this time this project is a simple PoC based on the [Open Cluster Management](https://open-cluster-management.io) project (OCM). The PoC allows to create `virtual kubernetes` instances, each running a subset of OCM Hub components.
This allows to easily provision *virtual hub* instances on a kubernetes host.

## Prereqs

To run the virtual cluster/virtual hub creation script, you will need the following:

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

## Creating a clusterset and a placement policy

Create a `clusterset` to represent a set of managed clusters:

```shell
kubectl apply -f deploy/ocm/example/clusterset1.yaml 
```  

`managedclusters` and `clustersets` are cluster-scoped resources, while placement policies
are namespace-scoped, so in order to apply a policy for a cluster set, we need also
to specify a `clustersetbinding`, which allows now to define policies in the bound 
`default` namespace. 

```shell
kubectl apply -f deploy/ocm/example/clusterset1-binding.yaml 
```

Add a label to the managed cluster to add the cluster to the clusterset, and another label
used to further refine selection:

```shell
kubectl label managedcluster cluster1 cluster.open-cluster-management.io/clusterset=clusterset1
kubectl label managedcluster cluster1 location=edge1
```

finally, create a placement policy to select clusters in the clusterset with the label `location=edge1`

```shell
kubectl apply -f deploy/ocm/example/placement1.yaml
```

check that policy produces a `placementdecision` and that it targets the cluster with the specified label 
(`cluster1`):

```shell
kubectl get placementdecisions

NAME                    AGE
placement1-decision-1   4m40s
```

You may also check the selected cluster in the `status` section:

```shell
kubectl describe placementdecision placement1-decision-1

Name:         placement1-decision-1
Namespace:    default
...
Status:
  Decisions:
    Cluster Name:  cluster1
    Reason:
```

For more details, consult the [Open Cluster Management documentation on placement policies](https://open-cluster-management.io/concepts/placement/) for more details.


## Deploying a workload on the managed clusters with ManifestWork

With OCM, you may create custom resources of kind [ManifestWork](https://open-cluster-management.io/concepts/manifestwork/) 
to wrap a set of resources to deploy on the managed clusters. A `manifestwork` resource is used to deploy a set of resources
to a single cluster, thus is should be placed on the namespace associated with a managed cluster (which in OCM has the same
name of the managed cluster).

Check that there is a namespace for `cluster1`:

```shell
kubectl get ns
NAME                          STATUS   AGE
kube-system                   Active   15h
...
cluster1                      Active   14h
```

and create a workload on `cluster1` with `manifestwork`:

```shell
kubectl apply -f deploy/ocm/example/manifestwork1.yaml -n cluster1
```

Check the status of the manifest to verify it has been applied on the managed cluster
and resources are available:

```shell
kubectl describe manifestwork -n cluster1 manifestwork1 
```

Open a new terminal, make sure `KUBECONFIG` is unset (e.g. `unset KUBECONFIG`) and set the context 
to point to `cluster1`:

```shell
kubectl config use-context kind-cluster1
```
and check that the resources in the manifestwork have been applied to the cluster:

```shell
kubectl get pods

NAME                                   READY   STATUS    RESTARTS   AGE
manifestwork1-nginx-58dc65cd95-bqkk8   1/1     Running   0          2m
```

```shell
$ kubectl get sa

NAME      SECRETS   AGE
default   1         15h
my-sa     1         20m
```

## Deploying a workload on the managed clusters with AppBundle

Manifestwork allows to deploy a workload to a single cluster. To target and deploy to multiple clusters
we introduce a new resource: `AppBundle` (Note that `appbundle` is not currently part of OCM, and it is still
a early stage PoC). AppBundle specs mirror the specs of ManifestWork, but allow to attach a label 
to identify a placement policy. An appbundle controller then retrieves the placement policy decision for that
policy and create a manifest work for each targeted cluster and place the manifest work(s) on each targeted 
cluster namespace. 

Take a look to this example of appbundle:

```shell
cat deploy/ocm/example/appbundle1.yaml 
```

The label `cluster.open-cluster-management.io/placement: placement1` binds the appbundle to the policy `placement1`.

Let's now deploy the appbundle:

```shell
kubectl apply -f deploy/ocm/example/appbundle1.yaml 
```

Check that a new manifestwork have been created, with the same name of the bundle:

```shell
kubectl get manifestworks -n cluster1

NAME            AGE
manifestwork1   23m
appbundle1      6m
```

You may theh check that the new deployment has been deployed to cluster1, going to the second terminal and running:

```shell
kubectl get pods

NAME                                   READY   STATUS    RESTARTS   AGE
appbundle1-nginx-54cc7fdb98-9qdnl      1/1     Running   0          2m59s
manifestwork1-nginx-58dc65cd95-bqkk8   1/1     Running   0          20m
```

## Deploying a workload on the managed clusters directly as a deployment

Since we are running a "virtual" hub, that represents a set of clusters, there are actually no
controllers for deployments, pods etc. on the virtual hub (this is a concept that has been 
lately of great interest on the kubernetes community, see for example the 
[kcp project](https://github.com/kcp-dev/kcp)). Then we can redefine the behavior of appliying a
deployment to the "virtual hub" - instead of creating pods on the virtual hub it will
create pods on the managed clusters that the virtual cluster represents.




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

