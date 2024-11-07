output "k3s_kubeconfig" {
  value = replace(
    replace(
      base64decode(
        replace(data.external.kubeconfig.result.kubeconfig, " ", "")
      ),
      "server: https://127.0.0.1:6443",
      "server: https://${var.name}:6443",
    ),
    "default",
    var.name,
  )
  sensitive = true
}
