module "flagger" {
  source = "../../../modules/flagger"

  kubeconfig_path = var.kubeconfig_path
}

variable "kubeconfig_path" {
  description = "The path to your .kube/config"
  default = "~/.kube/config"
}
