# teardown.ps1
# care 인프라 전체 종료 스크립트 (비용 방지)
# 사용법: PowerShell에서 ./teardown.ps1 실행

Write-Host "=== 1. Argo CD Application 삭제 ===" -ForegroundColor Cyan
Set-Location D:/care
kubectl delete -f argocd-app.yaml --ignore-not-found

Write-Host "=== 1-1. Ingress 삭제 + ALB 삭제 대기 ===" -ForegroundColor Cyan
kubectl delete ingress care-backend-ingress --ignore-not-found
for ($i = 0; $i -lt 30; $i++) {
    $lb = aws elbv2 describe-load-balancers --region ap-northeast-2 `
      --query "LoadBalancers[?starts_with(LoadBalancerName,'k8s-')].LoadBalancerArn" --output text
    if (-not $lb) { Write-Host "ALB 삭제 확인"; break }
    Write-Host "ALB 삭제 대기 중... ($i/30)"
    Start-Sleep -Seconds 10
}

Write-Host "=== 2. Argo CD 삭제 ===" -ForegroundColor Cyan
helm uninstall argocd -n argocd 2>$null
kubectl delete namespace argocd --ignore-not-found

Write-Host "=== 3. Prometheus + Grafana 삭제 ===" -ForegroundColor Cyan
helm uninstall monitoring -n monitoring 2>$null
kubectl delete namespace monitoring --ignore-not-found

Write-Host "=== 4. ECR 이미지 전체 삭제 (destroy 막힘 방지) ===" -ForegroundColor Cyan
$imageIds = aws ecr list-images --repository-name care --region ap-northeast-2 --query 'imageIds' --output json

if ($imageIds -and $imageIds -ne "[]") {
    $imageIds | Out-File -Encoding utf8 images.json
    aws ecr batch-delete-image --repository-name care --region ap-northeast-2 --image-ids file://images.json
    Remove-Item images.json
    Write-Host "ECR 이미지 삭제 완료"
} else {
    Write-Host "ECR에 삭제할 이미지 없음"
}

Write-Host "=== 5. EKS + 전체 인프라 삭제 (Terraform destroy) ===" -ForegroundColor Cyan
Set-Location D:/care/care-infra/environments/dev
$destroyTime = Measure-Command { terraform destroy -auto-approve }
Write-Host "Terraform destroy 소요 시간: $($destroyTime.TotalSeconds)초" -ForegroundColor Yellow

Write-Host "=== 6. 리소스 완전 삭제 확인 ===" -ForegroundColor Cyan

Write-Host "--- EKS ---"
aws eks list-clusters --region ap-northeast-2

Write-Host "--- EC2 (Running) ---"
aws ec2 describe-instances --region ap-northeast-2 --filters "Name=instance-state-name,Values=running" --query "Reservations[].Instances[].InstanceId"

Write-Host "--- NAT Gateway ---"
aws ec2 describe-nat-gateways --region ap-northeast-2 --filter "Name=state,Values=available" --query "NatGateways[].NatGatewayId"

Write-Host "--- Elastic IP ---"
aws ec2 describe-addresses --region ap-northeast-2 --query "Addresses[].AllocationId"

Write-Host "--- Load Balancer ---"
aws elbv2 describe-load-balancers --region ap-northeast-2 --query "LoadBalancers[].LoadBalancerName"

Write-Host ""
Write-Host "=== 종료 완료! 위 목록이 전부 빈 배열([])이면 정상 ===" -ForegroundColor Green