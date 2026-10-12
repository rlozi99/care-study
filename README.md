# care-study

AWS EKS + Argo CD(GitOps) + Terraform 인프라를 **공부하기 위한 정리본**입니다.
실제 서비스 코드(backend)와 접속 정보는 포함하지 않았습니다.

## 구성
| 폴더 | 내용 |
|---|---|
| `care-infra/` | Terraform (modules: vpc, eks, ecr / environments: dev, stage, prod) |
| `care-gitops/` | Kustomize 매니페스트 (base, overlays) |
| `argocd/` | Argo CD Application, 알림 설정 |
| `scripts/` | 셋업/종료 자동화 PowerShell 스크립트 |

## 값 처리 방식
- 내 공인 IP: Terraform 변수 `admin_cidr` 로 분리 → 환경변수 `TF_VAR_admin_cidr` 로 주입
- 토큰/DB 주소/JWT 키: 환경변수로만 사용 (`scripts/secrets.example.ps1` 참고)
- gitops YAML 의 `<MY_PUBLIC_IP>`, `<ACCOUNT_ID>` 는 자리표시자 (Kubernetes 매니페스트는 환경변수 치환이 안 되어 실제 사용 시 직접 교체)

- 서비스명·GitHub 아이디·저장소/버킷 이름은 일반 이름(`care`)과 자리표시자(`<GITHUB_USERNAME>`, `<STATE_BUCKET>` 등)로 바꿨습니다.

## 참고
- 공부용 정리본이라 실행은 하지 않습니다. 경로(`D:/care/...`)는 원본 환경 기준입니다.
