# setup.ps1
# care 인프라 초기 셋업 자동화 스크립트
# 사용법: PowerShell에서 ./setup.ps1 실행


# ===== 아래 값들은 본인 정보로 채워넣기 =====
$githubUsername = "<GITHUB_USERNAME>"
$gitopsRepoUrl = "https://github.com/<GITHUB_USERNAME>/<GITOPS_REPO>.git"
# 민감정보는 시크릿으로
$githubToken = $env:CARE_GH_TOKEN
$databaseUrl = $env:CARE_DB_URL
$jwtSecret = $env:CARE_JWT_SECRET

# 값 검증 블록 선 시행
$required = @{ githubToken = $githubToken; databaseUrl = $databaseUrl; jwtSecret = $jwtSecret; adminCidr = $env:TF_VAR_admin_cidr }
$missing = $required.GetEnumerator() | Where-Object { -not $_.Value }
if ($missing){
    Write-Host "다음 값이 비어있습니다: $($missing.Name -join ', ')" -ForegroundColor Red
    exit 1
}


try {
    $identity = aws sts get-caller-identity | ConvertFrom-Json
    Write-Host "AWS 연결 정상 - 계정: $($identity.Account)"
} catch {
    Write-Host "AWS 연결 안 됨, configure 진행"
    aws configure
}


Write-Host "=== 1. EKS 클러스터 생성 (Terraform) ===" -ForegroundColor Cyan
Set-Location D:/care/care-infra/environments/dev
$applyTime = Measure-Command { terraform apply -auto-approve }
Write-Host "Terraform apply 소요 시간: $($applyTime.TotalSeconds)초" -ForegroundColor Yellow

Write-Host "=== 2. kubeconfig 연결 ===" -ForegroundColor Cyan
aws eks update-kubeconfig --region ap-northeast-2 --name care-dev-cluster

Write-Host "=== 3. 노드 상태 확인 ===" -ForegroundColor Cyan
kubectl get nodes


Write-Host "=== GitHub Actions 트리거 (이미지 재빌드) ===" -ForegroundColor Cyan
Set-Location D:/care/care-backend
git commit --allow-empty -m "trigger: rebuild after infra reset"
git push origin main
Write-Host "GitHub Actions 실행 중... 완료까지 약 1~2분 소요" -ForegroundColor Yellow


Write-Host "=== 4. Argo CD 설치 ===" -ForegroundColor Cyan
kubectl create namespace argocd
helm repo add argo https://argoproj.github.io/argo-helm 2>$null
helm repo update
helm install argocd argo/argo-cd --namespace argocd

Write-Host "=== 5. Argo CD Pod 대기 (60초) ===" -ForegroundColor Cyan
Start-Sleep -Seconds 60
kubectl get pods -n argocd

Write-Host "=== 6. Argo CD 비밀번호 확인 ===" -ForegroundColor Cyan
$argoPassword = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | ForEach-Object { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }
Write-Host "Argo CD admin 비밀번호: $argoPassword" -ForegroundColor Yellow


Write-Host "=== 7. GitOps 레포 인증 등록 ===" -ForegroundColor Cyan
kubectl create secret generic care-gitops-repo `
  --namespace argocd `
  --from-literal=type=git `
  --from-literal=url=$gitopsRepoUrl `
  --from-literal=username=$githubUsername `
  --from-literal=password=$githubToken

kubectl label secret care-gitops-repo -n argocd argocd.argoproj.io/secret-type=repository


Write-Host "=== 8. Argo CD Application 등록 ===" -ForegroundColor Cyan
Set-Location D:/care
kubectl apply -f argocd-app.yaml


Write-Host "=== 9. K8s Secret 생성 (앱 환경변수) ===" -ForegroundColor Cyan
kubectl create secret generic care-secrets `
  --from-literal=DATABASE_URL=$databaseUrl `
  --from-literal=JWT_SECRET=$jwtSecret `
  --from-literal=PORT="3000" `
  --namespace=default

Write-Host "=== Pod Running 대기 ===" -ForegroundColor Cyan
$maxAttempts = 20
$attempt = 0
$allRunning = $false

while ($attempt -lt $maxAttempts -and -not $allRunning) {
    $pods = kubectl get pods -o json | ConvertFrom-Json
    $notRunning = $pods.items | Where-Object { $_.status.phase -ne "Running" }

    if ($notRunning.Count -eq 0 -and $pods.items.Count -gt 0) {
        $allRunning = $true
        Write-Host "모든 Pod가 Running 상태입니다"
    } else {
        Write-Host "대기 중... ($attempt/$maxAttempts) - 아직 Running 아닌 Pod: $($notRunning.Count)개"
        Start-Sleep -Seconds 10
        $attempt++
    }
}

if (-not $allRunning) {
    Write-Host "제한 시간 내에 Pod가 Running 되지 않았습니다. 수동 확인 필요" -ForegroundColor Red
}


Write-Host "=== 10. metrics-server 설치 (HPA용) ===" -ForegroundColor Cyan
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml


Write-Host "=== 11. Prometheus + Grafana 설치 ===" -ForegroundColor Cyan
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>$null
helm repo update
kubectl create namespace monitoring
helm install monitoring prometheus-community/kube-prometheus-stack --namespace monitoring

Write-Host "=== Grafana Pod 대기 (60초) ===" -ForegroundColor Cyan
Start-Sleep -Seconds 60
kubectl get pods -n monitoring

Write-Host "=== Grafana 비밀번호 확인 ===" -ForegroundColor Cyan
$grafanaPassword = kubectl get secret monitoring-grafana -n monitoring -o jsonpath="{.data.admin-password}" | ForEach-Object { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }
Write-Host "Grafana admin 비밀번호: $grafanaPassword" -ForegroundColor Yellow


Write-Host "=== 12. 전체 상태 확인 (30초 대기 후) ===" -ForegroundColor Cyan
Start-Sleep -Seconds 30
kubectl get application -n argocd
kubectl get pods
kubectl get hpa
kubectl get pods -n monitoring

Write-Host "=== 셋업 완료! ===" -ForegroundColor Green
Write-Host ""
Write-Host "다음 명령어로 접속하세요:" -ForegroundColor Cyan
Write-Host "Argo CD: kubectl port-forward svc/argocd-server -n argocd 8080:443"
Write-Host "Grafana: kubectl port-forward svc/monitoring-grafana -n monitoring 3001:80"
Write-Host "care 앱: kubectl port-forward svc/care-backend-svc 3000:80"