# Runtime Detection (Falco)

Everything else in this project secures the artifact *before* it runs: build,
scan, sign, attest, and verify at admission. But a verified, signed image can
still be exploited once it's running. Runtime detection is the layer that
watches what containers actually *do* and flags suspicious behavior live.

I use [Falco](https://falco.org), which reads kernel syscalls (via a modern eBPF
probe) and matches them against rules like "a sensitive file was read" or "a
shell was spawned in a container."

## What it adds to the threat model

The build-time pillars answer "is this the artifact I expect?" Falco answers a
different question: "is this artifact, now running, behaving the way it should?"
That's defense in depth. A compromised dependency that passed every scan can
still try to read credentials or open a reverse shell at runtime, and that's
what Falco is positioned to catch.

## Setup

Falco installs into the cluster with Helm. The modern eBPF driver needs a kernel
with BTF (`/sys/kernel/btf/vmlinux`), which kind nodes have:

```bash
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update
helm install falco falcosecurity/falco \
  --namespace falco --create-namespace \
  --set driver.kind=modern_ebpf --set tty=true

kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=falco \
  -n falco --timeout=180s
```

Falco runs as a DaemonSet (one pod per node) and writes alerts to stdout, so you
read them with `kubectl logs`.

## Demo: detect an attack on a running container

My own app image is distroless, so it has no shell for an attacker to spawn in
the first place (defense in depth from the build side). To show Falco actually
firing, deploy a normal pod with a shell to stand in for a compromised workload:

```bash
kubectl run target --image=ubuntu:24.04 --restart=Never --command -- sleep infinity
kubectl wait --for=condition=Ready pod/target --timeout=120s
```

Now simulate an attacker reading the password-hash file inside the container:

```bash
kubectl exec target -- cat /etc/shadow
```

Falco catches it instantly. Read its verdict:

```bash
kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco --tail=50 \
  | grep "Sensitive file opened"
```

```
Warning Sensitive file opened for reading by non-trusted program |
  file=/etc/shadow process=cat command=cat /etc/shadow
  container_name=target container_image=ubuntu:24.04
  k8s_pod_name=target k8s_ns_name=default
```

That single line is the whole point: full forensic context (file, process,
command, container, image, pod, namespace) the moment the syscall happened, with
no change to the workload itself.

## Cleanup

```bash
kubectl delete pod target
helm uninstall falco -n falco
```

(Or just `scripts/cluster-down.ps1` to remove the whole cluster.)
