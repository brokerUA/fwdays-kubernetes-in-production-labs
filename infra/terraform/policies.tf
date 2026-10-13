resource "kubectl_manifest" "require_readonly_rootfs" {
  yaml_body = <<-YAML
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: require-readonly-rootfs
    spec:
      validationFailureAction: Audit
      rules:
        - name: check-readonly-rootfs
          match:
            any:
              - resources:
                  kinds:
                    - Pod
          validate:
            message: "Containers must use a read-only root filesystem."
            pattern:
              spec:
                containers:
                  - securityContext:
                      readOnlyRootFilesystem: true
  YAML

  depends_on = [helm_release.kyverno]
}

resource "kubectl_manifest" "add_person_label" {
  yaml_body = <<-YAML
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: add-person-label
    spec:
      validationFailureAction: Enforce
      rules:
        - name: add-student-label
          match:
            any:
              - resources:
                  kinds:
                    - Pod
                  namespaces:
                    - student01
                    - student02
                    - student03
          mutate:
            patchStrategicMerge:
              metadata:
                labels:
                  person: student
        - name: add-mentor-label
          match:
            any:
              - resources:
                  kinds:
                    - Pod
                  namespaces:
                    - mentor
          mutate:
            patchStrategicMerge:
              metadata:
                labels:
                  person: mentor
  YAML

  depends_on = [helm_release.kyverno]
}
