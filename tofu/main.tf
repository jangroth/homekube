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
  name       = "argocd" #FIXME: should be 'argo-cd'
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  version    = var.argocd_version
  values = [
    file("${path.module}/values/argocd.yaml")
  ]
}

resource "kubectl_manifest" "argocd_root_app" {
  yaml_body = file("${path.module}/manifests/argocd-root-app.yaml")
  depends_on = [
    helm_release.argocd
  ]
}
