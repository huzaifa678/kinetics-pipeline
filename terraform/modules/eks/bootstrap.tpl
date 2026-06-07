#cloud-config
write_files:
  - path: /etc/eks/eks.yaml
    content: |
      apiVersion: node.eks.aws/v1alpha1
      kind: NodeConfig
      spec:
        cluster:
          name: "${cluster_name}"
          apiServerEndpoint: "${cluster_endpoint}"
          certificateAuthority: "${cluster_ca}"
          cidr: "${cidr}" 

runcmd:
  - /usr/bin/nodeadm init --config-source file:///etc/eks/eks.yaml --daemon kubelet --daemon containerd