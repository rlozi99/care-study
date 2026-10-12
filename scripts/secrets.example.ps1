# secrets.example.ps1  (예시 파일 - 실제 값은 넣지 말 것)
# 사용법: 이 파일을 secrets.local.ps1 로 복사해 값을 채운 뒤, 같은 PowerShell 창에서 먼저 실행
#   . .\secrets.local.ps1
# secrets.local.ps1 은 .gitignore 로 제외되어 있어 GitHub 에 올라가지 않는다.

$env:CARE_GH_TOKEN    = "<GitHub 토큰>"
$env:CARE_DB_URL      = "<DB 접속 주소>"
$env:CARE_JWT_SECRET  = "<랜덤 비밀키>"
$env:TF_VAR_admin_cidr  = "<내 공인 IP>/32"   # Terraform 이 var.admin_cidr 로 자동 인식
