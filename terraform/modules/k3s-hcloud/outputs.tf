output "k3s_kubeconfig" {
  value = replace(
    replace(
      base64decode(
        replace(data.external.kubeconfig.result.kubeconfig, " ", "")
      ),
      "server: https://127.0.0.1:6443",
      # The API is not exposed publicly; reach it through a local SOCKS proxy over SSH
      "server: https://${var.name}:6443\n    proxy-url: socks5://127.0.0.1:1080",
    ),
    "default",
    var.name,
  )
  sensitive = true
}
