# Examples of using OCM

## Placement
Please note that for the placement to work, managedclusters need to be labelled with a label indicating the set they belong to:

```
kubectl label managedcluster cluster1 cluster.open-cluster-management.io/clusterset=clusterset1
```

Then follow example in [placement](https://github.com/open-cluster-management-io/placement)

```
cat <<EOF | kubectl apply -f -
apiVersion: cluster.open-cluster-management.io/v1beta1
kind: ManagedClusterSet
metadata:
  name: clusterset1
EOF
```

```
cat <<EOF | kubectl apply -f -
apiVersion: cluster.open-cluster-management.io/v1beta1
kind: ManagedClusterSetBinding
metadata:
  name: clusterset1
  namespace: default
spec:
  clusterSet: clusterset1
EOF
```

label one or more cluster with additional label for furher selection

```
kubectl label managedcluster podman2 location=edge1
```


```
cat <<EOF | kubectl apply -f -
apiVersion: cluster.open-cluster-management.io/v1alpha1
kind: Placement
metadata:
  name: placement1
  namespace: default
spec:
  predicates:
    - requiredClusterSelector:
        labelSelector:
          matchLabels:
            location: edge1
EOF
```