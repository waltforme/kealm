# Examples of using OCM

## Placement
Please note that for the placement to work, managedclusters need to be labelled with a label indicating the set they belong to:

```
kubectl label managedcluster cluster1 cluster.open-cluster-management.io/clusterset=clusterset1
```