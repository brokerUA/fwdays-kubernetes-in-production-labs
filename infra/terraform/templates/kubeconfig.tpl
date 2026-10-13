apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: ${base64encode(ca_cert)}
    server: ${server}
  name: ${cluster_name}
contexts:
- context:
    cluster: ${cluster_name}
    namespace: ${default_namespace}
    user: ${user_name}
  name: ${user_name}@${cluster_name}
current-context: ${user_name}@${cluster_name}
users:
- name: ${user_name}
  user:
    token: ${token}
