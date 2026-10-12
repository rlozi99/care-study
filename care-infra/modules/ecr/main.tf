variable "project_name" {}

resource "aws_ecr_repository" "main" {
  name                 = var.project_name
  image_tag_mutability = "MUTABLE"
  force_delete          = true      # Allow deletion of the repository even if it contains images

  image_scanning_configuration {
    scan_on_push = true
  }
/*
  lifecycle {
    prevent_destroy = true
  }
*/
  tags = {
    Name = "${var.project_name}-ecr"
  }
}

resource "aws_ecr_lifecycle_policy" "main" {
  repository = aws_ecr_repository.main.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "최근 이미지 10개만 유지"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}

output "repository_url" { value = aws_ecr_repository.main.repository_url }