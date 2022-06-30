output "k3s_kubeconfig" {
  value = replace(
    replace(
      base64decode(
        replace(data.external.kubeconfig.result.kubeconfig, " ", "")
      ),
      "server: https://127.0.0.1:6443",
      "server: https://k3s.${var.domain}:6443",
    ),
    "default",
    "k3s",
  )
  sensitive = true
}
