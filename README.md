# kealm
Kubernetes at the Edge Application Lifecycle Management


# Hacks

## Experiments with OCM

cat <<EOF | kubectl --context ${CTX_HUB_CLUSTER} apply -f -
apiVersion: cluster.open-cluster-management.io/v1beta1
kind: ManagedClusterSet
metadata:
  name: clusterset1
EOF

cat <<EOF | kubectl --context ${CTX_HUB_CLUSTER} apply -f -
apiVersion: cluster.open-cluster-management.io/v1beta1
kind: ManagedClusterSetBinding
metadata:
  name: clusterset1
  namespace: default
spec:
  clusterSet: clusterset1
EOF

cat <<EOF | kubectl --context ${CTX_HUB_CLUSTER} apply -f -
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
            environment: dev
EOF

cat <<EOF | kubectl --context ${CTX_HUB_CLUSTER} apply -f -
apiVersion: cluster.open-cluster-management.io/v1alpha1
kind: Placement
metadata:
  name: placement2
  namespace: default
spec:
  numberOfClusters: 2
  clusterSets:
    - clusterset1
EOF

## Experiments with Kine and KCP:

1. Follow [this guide](https://github.com/k3s-io/kine/tree/master/examples)

