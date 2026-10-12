variable "admin_cidr" {
  type        = string
  description = "EKS API 서버에 접근을 허용할 내 공인 IP (예: 203.0.113.10/32). 값은 코드에 쓰지 않고 환경변수 TF_VAR_admin_cidr 로 넣는다."
}
