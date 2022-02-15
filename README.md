# kealm

Kubernetes Edge Application Lifecycle Management.

At this time this project is a simple PoC based on the [Open Cluster Management](https://open-cluster-management.io) project (OCM). The PoC allows creation of *virtual hub* instances, each running a subset of OCM Hub components.
This allows to easily provision multiple virtual hub instances on a kubernetes host.

## Prereqs

To run the virtual cluster/virtual hub creation script, you will need the following:

- docker
- KinD
- kubectl
- [clusteradm](https://github.com/open-cluster-management-io/clusteradm/releases)

## Creating a virtual cluster

Clone this project:

```shell
git clone https://github.com/pdettori/kealm.git
cd kealm
```

Add the `vh` plugin to your path:

```shell
export PATH=$PATH:$(pwd)/deploy
```

Tip: you may add this statement to your ~/.bash_profile:

```shell
echo "export PATH=\$PATH:$(pwd)/deploy" >> ${HOME}/.profile 
source ${HOME}/.profile
```

If your host cluster machine has an external IP you may set the `EXTERNAL_IP` env variable to that IP.

Create a kubernetes host to run the virtual hubs. This creates a Kind cluster:

```shell
make create-cluster
```

Note: The current script to create virtual hubs has been tested only on KinD; since the script assume the availability of specific node ports, you have to use the supplied make command to create it.

To create a new virtual hub named *vks1*, run the command:

```shell
kubectl vh create vks1
```

this will create a virtual hub instance named *vks1* in the kind cluster. To check the progress
and results, you may check the logs for the pod started in a job:

```shell
kubectl logs -l job-name=vks1-job -f
```

After the job completes, you will get a message similar to:

```shell
...
cluster manager has been started! To join clusters run the command (make sure to use the correct <cluster-name>:

clusteradm join --hub-token <token> --hub-apiserver <api-server-url> --cluster-name <cluster-name>
```

You may now check the status of the virtual cluster by checking the pods running in the `<virtual hub name>-system` namespace:

e.g.

```shell
kubectl get pods -n vks1-system
```

```shell
NAME                                                       READY   STATUS    RESTARTS   AGE
cluster-manager-extensions-54b758b6d5-qx86t                1/1     Running   0          3h24m
cluster-manager-placement-controller-b9b8b4f67-b6t5q       1/1     Running   0          3h24m
cluster-manager-registration-controller-6769f48c79-vwlqg   1/1     Running   0          3h24m
kube-apiserver-6b75c996d8-fh5zx                            2/2     Running   3          3h25m
kube-controller-manager-58b46767b8-4jskt                   1/1     Running   2          3h24m
```

Define the context for the new virtual hub by running:

```shell
kubectl vh merge-kubeconfig vks1
```

Create a new managed cluster. To create one named `cluster1` using kind:

```shell
kind create cluster --name cluster1
```

To add `cluster1` to the hub, switch to the context of `cluster1` and use the join command that was printed at the end of the log above. Be sure to subsitute `cluster1` for `<cluster-name>`.

```shell
kubectl config use-context kind-cluster1

clusteradm join --hub-token <token> --hub-apiserver <api-server-url> --cluster-name <cluster-name>
```

Once the OCM agents are installed on `cluster1` and started, you should see a message similar to:

```shell
Waiting for the management components to become ready...
Please log onto the hub cluster and run the following command:

    clusteradm accept --clusters cluster1
```

The (virtual) hub must accept the join request. To do so, switch to the hub context:

```shell
kubectl config use-context vks1
```

You should be ablel to see a pending certificate signing request (CSR) for `cluster1`. For example:

```shell
kubectl get csr
```

```shell
NAME             AGE     SIGNERNAME                            REQUESTOR                                                         REQUESTEDDURATION   CONDITION
cluster1-2b8hp   4m20s   kubernetes.io/kube-apiserver-client   system:serviceaccount:open-cluster-management:cluster-bootstrap   <none>              Pending
```

Accept the cluster join request to approve the CSR:

```shell
clusteradm accept --clusters cluster1
```

Verify that the new cluster is joined and available by inspecting the list of managed clusters:

```shell
kubectl get managedclusters
```

```shell
NAME       HUB ACCEPTED   MANAGED CLUSTER URLS          JOINED   AVAILABLE   AGE
cluster1   true           https://192.168.1.153:31433   True     True        4m43s
```

## Creating a clusterset and a placement policy

Create a `clusterset` to represent a set of managed clusters:

```shell
kubectl apply -f examples/clusterset1.yaml 
```  

`managedclusters` and `clustersets` are cluster-scoped resources, while placement policies
are namespace-scoped, so in order to apply a policy for a `clusterset`, we need also
to specify a `clustersetbinding`, which allows now to define policies in the bound `default` namespace.

```shell
kubectl apply -f examples/clusterset1-binding.yaml 
```

Add a label to the managed cluster to add the cluster to the clusterset, and another label
used to further refine selection:

```shell
kubectl label managedcluster cluster1 cluster.open-cluster-management.io/clusterset=clusterset1
kubectl label managedcluster cluster1 location=edge1
```

Finally, create a placement policy to select clusters in the clusterset with the label `location=edge1`

```shell
kubectl apply -f examples/placement1.yaml
```

Check that policy produces a `placementdecision` and that it targets the cluster with the specified label (`cluster1`):

```shell
kubectl get placementdecisions
```

```shell
NAME                    AGE
placement1-decision-1   4m40s
```

and:

```shell
kubectl describe placementdecision placement1-decision-1
```

```shell
Name:         placement1-decision-1
Namespace:    default
...
Status:
  Decisions:
    Cluster Name:  cluster1
    Reason:
```

For more details, consult the [Open Cluster Management documentation on placement policies](https://open-cluster-management.io/concepts/placement/).

## Deploying a workload on the managed clusters with ManifestWork

With OCM, you may create custom resources of kind [ManifestWork](https://open-cluster-management.io/concepts/manifestwork/) to wrap a set of resources to deploy on the managed clusters. A `ManifestWork` resource is used to deploy a set of resources to a single cluster, thus it should be placed on the namespace associated with a managed cluster (which in OCM has the same name of the managed cluster).

Check that there is a namespace for `cluster1`:

```shell
kubectl get ns
```

```shell
NAME                          STATUS   AGE
kube-system                   Active   15h
...
cluster1                      Active   14h
```

and create a workload on `cluster1` with `manifestwork`:

```shell
kubectl apply -f examples/manifestwork1.yaml -n cluster1
```

Check the status of the manifest to verify it has been applied on the managed cluster
and resources are available:

```shell
kubectl describe manifestwork -n cluster1 manifestwork1 
```

Switch to cluster1 context:

```shell
kubectl config use-context kind-cluster1
```

and check that the resources in the manifestwork have been applied to the cluster:

```shell
kubectl get pods
```

``` shell
NAME                                   READY   STATUS    RESTARTS   AGE
manifestwork1-nginx-58dc65cd95-bqkk8   1/1     Running   0          2m
```

```shell
kubectl get sa
```

```shell
NAME      SECRETS   AGE
default   1         15h
my-sa     1         20m
```

## Deploying a workload on the managed clusters with AppBundle

A `ManifestWork` allows to deploy a workload to a single cluster. To target and deploy to multiple clusters
we introduce a new resource: `AppBundle` (Note that `appbundle` is not currently part of OCM, and it is still
an early stage PoC). `AppBundle` specs mirror the specs of `ManifestWork`, but allows to attach a label to bind a placement policy. An `AppBundle` controller then retrieves the placement policy decision for that
policy, creates a `ManifestWork` for each targeted cluster and places the `ManifestWork`(s) on each targeted cluster namespace.

Take a look to this example of appbundle:

```shell
cat examples/appbundle1.yaml 
```

The label `cluster.open-cluster-management.io/placement: placement1` binds the appbundle to the policy `placement1`.

Let's now switch back to vks and deploy the appbundle:

```shell
kubectl config use-context vks1
kubectl apply -f examples/appbundle1.yaml 
```

Check that a new `manifestwork` has been created, with the same name of the bundle:

```shell
kubectl get manifestworks -n cluster1
```

```shell
NAME            AGE
manifestwork1   23m
appbundle1      6m
```

You may then check that the new deployment has been deployed to cluster1:

```shell
kubectl config use-context kind-cluster1
kubectl get pods
```

```shell
NAME                                   READY   STATUS    RESTARTS   AGE
appbundle1-nginx-54cc7fdb98-9qdnl      1/1     Running   0          2m59s
manifestwork1-nginx-58dc65cd95-bqkk8   1/1     Running   0          20m
```

## Deploying a workload on the managed clusters directly as a deployment

Since we are running a *virtual* hub, representing a fleet of clusters, there are actually no
controllers for deployments, pods etc. on the virtual hub (this is a concept that has been lately of great interest on the kubernetes community, see for example the [kcp project](https://github.com/kcp-dev/kcp)). Then we can redefine the behavior of applying a
deployment to the *virtual hub* - instead of creating pods on the virtual hub, it will
create pods on the managed clusters.

This model will still use the `AppBundle` resource to back the resources applied to the virtual hub,
so we will need to create an empty `AppBundle` associated with a placement policy:

```shell
kubectl config use-context vks1
kubectl apply -f examples/appbundle2-empty.yaml
```

We can then apply a deployment associated with this new bundle:

```shell
kubectl apply -f examples/deployment1.yaml 
```

check that pods are NOT created on the virtual cluster:

```shell
kubectl get pods 
```

```shell
No resources found in default namespace.
```

verify that `appbundle2` includes the new deployment:

```shell
kubectl describe appbundle appbundle2
```

Verify that the new deployment has been delivered to the managed cluster:

```shell
kubectl config use-context kind-cluster1
kubectl get pods
```

```shell
NAME                                   READY   STATUS    RESTARTS   AGE
appbundle1-nginx-54cc7fdb98-9qdnl      1/1     Running   0          59m
appbundle2-nginx-5d976d46f5-w7phc      1/1     Running   0          3m41s
manifestwork1-nginx-58dc65cd95-bqkk8   1/1     Running   0          76m
```

## HowTo

### Get Virtual Hub kubeconfig

```shell
kubectl vh print-kubeconfig <vh name>
```

### Get Virtual Hub join command

```shell
kubectl vh print-join <vh name>
```

### Delete Virtual Hub instance

```shell
kubectl vh delete <vh name>
```

### Listing DBs

```shell
kubectl vh psql
```

then type `\l`

### Hacking flotta

Install CRDs

```
kubectl apply -f config/crd/bases/management.project-flotta.io_edgedevices.yaml 
kubectl apply -f config/crd/bases/management.project-flotta.io_edgedeployments.yaml 
```

