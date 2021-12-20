## steps to enable bootstrapping

On VC cluster: (steps extracted from [this article](https://ansilh.com/18-tls_bootstrapping/02-bootstrapping-with-token/))


```
kubectl apply -f vc/csr-roles-and-bindings.yaml
```

create bootstrap token
```
TOKEN_ID=$(openssl rand -hex 3)
TOKEN_SECRET=$(openssl rand -hex 8)
TOKEN=$TOKEN_ID.$TOKEN_SECRET

echo $TOKEN


cat <<EOF | kubectl create -f -
apiVersion: v1
kind: Secret
metadata:
  # Name MUST be of form "bootstrap-token-<token id>"
  name: bootstrap-token-$TOKEN_ID
  namespace: kube-system

# Type MUST be 'bootstrap.kubernetes.io/token'
type: bootstrap.kubernetes.io/token
stringData:
  # Human readable description. Optional.
  description: "The default bootstrap token."

  # Token ID and secret. Required.
  token-id: $TOKEN_ID
  token-secret: $TOKEN_SECRET

  # Expiration. Optional.
  expiration: 2022-12-05T12:00:00Z

  # Allowed usages.
  usage-bootstrap-authentication: "true"
  usage-bootstrap-signing: "true"

  # Extra groups to authenticate the token as. Must start with "system:bootstrappers:"
  auth-extra-groups: system:bootstrappers:worker,system:bootstrappers:ingress
EOF
```

(for kind only): grab the address for the master that will be used by each managed cluster to bootstrap:

```
docker inspect <kind container name> | grep IPAddress    # e.g. docker inspect vch1-control-plane | grep IPAddress
```

e.g. 172.18.0.3

Check also the node port used in the host cluster:

```
k get services | grep NodePort
ip-172-31-37-22              NodePort    10.96.142.173   <none>        7443:30443/TCP   34h
````

In this case it's 30443. Then build the server address:

```
SERVER=https://172.18.0.3:30443
```

Then build a config:

```
CERTS_PATH=/etc/kubernetes/pki

kubectl config set-cluster bootstrap \
  --kubeconfig=bootstrap-kubeconfig-public  \
  --server=$SERVER \
  --certificate-authority=${CERTS_PATH}/ca.crt \
  --embed-certs=true

kubectl -n kube-public create configmap cluster-info \
  --from-file=kubeconfig=bootstrap-kubeconfig-public  

kubectl -n kube-public get configmap cluster-info -o yaml
```

add RBAC for allowing join request from managed cluster:

```
k apply -f vc/0000_03_bootstrap_role_and_binding.yaml 
```

Now find the token for join request:

```
kubectl get secrets -n open-cluster-management cluster-bootstrap-token-86l7q  -o json | jq -r '.data.token' | base64 -d
```

Finally, run clusteradm join command (with kubectx pointimg to managed cluster !)

e.g.

```
clusteradm join --hub-token eyJhbGciOiJSUzI1NiIsImtpZCI6IjZTWlgwLUMwWEQwWGc2dWxrTkd4RV9JX0dPXy1xOTh3Zy1aTXQzbzFnSjAifQ.eyJpc3MiOiJrdWJlcm5ldGVzL3NlcnZpY2VhY2NvdW50Iiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9uYW1lc3BhY2UiOiJvcGVuLWNsdXN0ZXItbWFuYWdlbWVudCIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VjcmV0Lm5hbWUiOiJjbHVzdGVyLWJvb3RzdHJhcC10b2tlbi04Nmw3cSIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VydmljZS1hY2NvdW50Lm5hbWUiOiJjbHVzdGVyLWJvb3RzdHJhcCIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VydmljZS1hY2NvdW50LnVpZCI6IjAxMTI2MDcyLTU3NDktNGFiMy04Y2QzLTJkMWVlNGE3ZGYwZSIsInN1YiI6InN5c3RlbTpzZXJ2aWNlYWNjb3VudDpvcGVuLWNsdXN0ZXItbWFuYWdlbWVudDpjbHVzdGVyLWJvb3RzdHJhcCJ9.XSjnycEwZucEC2mlt1uDXRZhBuJRHs-FMEhvXVhxFGN3vppXDo1NXrhjuIc2upGKIs7Svmcc6Hq-DyA9xl6NRLj6WlYZHyIkF7eWtF2fdPMJDBowIE9S0Xa7efmGSGMl2BoegK8bMhlfqleBCRZnFAUnY0VckUw6iSDupQSyzp8TEFDj00cXpP6rPB6t98ZI1B2rSwP3ZloxYrcUmrABea57Y9-0e03USxOa-mtxEO-TcRuvZhp524QuybNEqoBrrbleYg073B963jhgRTepgFGQGPDiw8d-HU9El5ulcsZjnhDh0LObbVMWsN4ANo2P959LW_EHDc8WopDV3ol6VA --hub-apiserver https://172.18.0.3:30443 --cluster-name cluster1
```

On vc, check for csr created:

```

## Updating certs

The commmand above may result in following error:

```
k logs -n open-cluster-management-agent klusterlet-registration-agent-679576cd6c-fsqwj                                 

...
x509: certificate is valid for 10.96.0.1, 172.31.37.22, norsion=0": x509: certificate is valid for 10.96.0.1, 172t 172.18.0.3        
...                                             
```

Steps to add host IP to cert: (based on this [article](https://blog.scottlowe.org/2019/07/30/adding-a-name-to-kubernetes-api-server-certificate/))

Add kubeadm config to cluster. With Kubectl pointing to virtual cluster, run:

```
kubeadm init phase upload-config kubeadm
kubectl -n kube-system get configmap kubeadm-config -o jsonpath='{.data.ClusterConfiguration}' > kubeadm.yaml
```

Then edit kubeadm.yaml to add the SANs you need (the default SANs will stay there)

```yaml
apiServer:
    certSANs:
    - "172.18.0.3"
...
```

First, move the existing API server certificate and key (if kubeadm sees that they already exist in the designated location, it won’t create new ones):

```
sudo chmod a+rw /etc/kubernetes/pki
mv /etc/kubernetes/pki/apiserver.{crt,key} ~
```

Then, use kubeadm to just generate a new certificate:

```
kubeadm init phase certs apiserver --config kubeadm.yaml
```

Re-create the secrets for the certs (make sure to be in the right context)

```
# switch context - e.g. kubectx kind-vch1
./create-secret.sh
```

Restart API server pod, e.g.:

```
kubectl delete pod kube-apiserver-d9d4548b4-q7pf5
```


### Debugging stuff


clusteradm join --hub-token eyJhbGciOiJSUzI1NiIsImtpZCI6IjZTWlgwLUMwWEQwWGc2dWxrTkd4RV9JX0dPXy1xOTh3Zy1aTXQzbzFnSjAifQ.eyJpc3MiOiJrdWJlcm5ldGVzL3NlcnZpY2VhY2NvdW50Iiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9uYW1lc3BhY2UiOiJvcGVuLWNsdXN0ZXItbWFuYWdlbWVudCIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VjcmV0Lm5hbWUiOiJjbHVzdGVyLWJvb3RzdHJhcC10b2tlbi04Nmw3cSIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VydmljZS1hY2NvdW50Lm5hbWUiOiJjbHVzdGVyLWJvb3RzdHJhcCIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VydmljZS1hY2NvdW50LnVpZCI6IjAxMTI2MDcyLTU3NDktNGFiMy04Y2QzLTJkMWVlNGE3ZGYwZSIsInN1YiI6InN5c3RlbTpzZXJ2aWNlYWNjb3VudDpvcGVuLWNsdXN0ZXItbWFuYWdlbWVudDpjbHVzdGVyLWJvb3RzdHJhcCJ9.XSjnycEwZucEC2mlt1uDXRZhBuJRHs-FMEhvXVhxFGN3vppXDo1NXrhjuIc2upGKIs7Svmcc6Hq-DyA9xl6NRLj6WlYZHyIkF7eWtF2fdPMJDBowIE9S0Xa7efmGSGMl2BoegK8bMhlfqleBCRZnFAUnY0VckUw6iSDupQSyzp8TEFDj00cXpP6rPB6t98ZI1B2rSwP3ZloxYrcUmrABea57Y9-0e03USxOa-mtxEO-TcRuvZhp524QuybNEqoBrrbleYg073B963jhgRTepgFGQGPDiw8d-HU9El5ulcsZjnhDh0LObbVMWsN4ANo2P959LW_EHDc8WopDV3ol6VA --hub-apiserver https://172.18.0.3:30443 --cluster-name cluster1


## References

- Join flow for OCM agent is documented (here)[https://github.com/open-cluster-management-io/api/blob/main/docs/clusterjoinprocess.md]