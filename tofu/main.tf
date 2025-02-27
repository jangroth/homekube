resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
    annotations = {
      "opentofu.org/managed-by" = "opentofu"
      "opentofu.org/version"    = "1.9.0"
      "opentofu.org/module"     = "bootstrap"
    }
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  version    = "7.8.5"
  values = [
    file("${path.module}/values/argocd.yaml")
  ]
}
