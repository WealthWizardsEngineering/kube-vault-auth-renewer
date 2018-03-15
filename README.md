# Kubernetes Vault Auth Renewer Docker Image

This Docker image is designed to keep [Vault](https://www.vaultproject.io) auth tokens and secret leases alive for the
life time of a Kubernetes pod. This should be run as a sidecar to containers that are unaware of Vault and secrets
are injected to them at startup and cannot be changed. This allows public Docker images to be with Vault used
without modification.

Vault is designed to ensure that secrets are only available for as long as they are needed, this means that most of
Vault secrets engines (e.g. the [Consul Secrets Engine](https://www.vaultproject.io/docs/secrets/consul/index.html))
will rovoke secrets they have given out after a periods of time (ttl). This means that even if a secret is exposed
the window that the secret can be used is limited.

Secrets can be renewed, so that they don't expire, but this is a continual process. Docker containers that are not
aware of Vault are given secrets at start up and they expect them to be valid for the lifetime of the container.
This image is designed to be run as a Kubernetes sidecar within the same pod and periodically check the leases for
the authentication token and secret leases to see if they need renewing and renew them if necessary. This means
that the secrets remain valid for the lifetime of the pod.

Once the pod is terminated, the auth token and secrets are left to expire.

This can be used in conjunction with the Kubernetes Vault Auth Init image which will authenticate against Vault
and provide a mechanism for injecting the secrets into your service container. 

## Prerequisites

This container requires a valid Vault auth token as an environmental variable, with a sensible ttl that works with the
renewal interval of this container.
 
## Configuration

The following environment variables are required:

* VAULT_ADDR - the URL of your Vault server

The following environment variables are optional:

* RENEW_INTERVAL - the number of seconds to wait before checking leases, defaults to 6 hours

The following can be set as environment variables, but if you are using the Kubernetes Vault Auth Renewer init
container these will be read from /env/variables, this requires a shared volume to be mounted between the init
container and this on /env.
 
* VAULT_TOKEN - the vault auth token to use and keep alive
* LEASE_IDS - a comma separated list of lease ids to keep alive,
e.g. consul/creds/my-role/619ceafd-9968-b338-2d3e-93c987654321,consul/creds/my-role/619ceafd-9968-b338-2d3e-93c123456789

# TTLs and the renewal interval

In order to avoid your auth token or secrets from expiring you need to make sure that they won't expire in between
checks, which means their TTL must exceed the RENEW_INTERVAL plus a tolerance. It is suggested that you set the TTLS to
at least 2-3 times the RENEW_INTERVAL.

Minor discrepancies in the time leases are created might mean that they have to wait an extra cycle before
they are renewed, so you should avoid ttls that might expire seconds before a renewal cycle.

# Kubernetes deployment

This is an example that uses the Kubernetes Vault Auth Init container and this as a sidecar

kubectl apply -f myfile.yml

```
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app-service-account
---
kind: Deployment
apiVersion: extensions/v1beta1
metadata:
  name: my-app
  annotations:
    tags: my-app
spec:
  replicas: 1
  minReadySeconds: 35
  revisionHistoryLimit: 3
  strategy:
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: my-app
        tier: backend
    spec:
      serviceAccountName: my-app-service-account
      volumes:
      - name: shared-data
        emptyDir: {}
      initContainers:
      - name: vault-init
        image: daveshepherd/kubernetes-vault-auth-init
        env:
        - name: KUBERNETES_AUTH_PATH
          value: "kubernetes"
        - name: VAULT_ADDR
          value: "https://vault.example.com"
        - name: VAULT_LOGIN_ROLE
          value: "my-app-role"
        - name: SECRET_SOME_SECRET
          value: "secret/from/somewhere"
        volumeMounts:
        - name: shared-data
          mountPath: /env
      containers:
      - name: vault-renewer
        image: daveshepherd/kubernetes-vault-auth-renewer
        env:
        - name: VAULT_ADDR
          value: "https://vault.example.com"
        volumeMounts:
        - name: shared-data
          mountPath: /env
      - name: my-app
        image: my-app
        imagePullPolicy: Always
        terminationMessagePath: "/var/log/my-app_termination.log"
        command: ["/bin/sh", "-c", "source /env/variables; ./run-my-app.sh"]
        volumeMounts:
        - name: shared-data
          mountPath: /env
```
