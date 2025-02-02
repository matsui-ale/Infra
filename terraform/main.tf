provider "aws" {
  region = "sa-east-1"
}

terraform {
  backend "s3" {
    bucket = "tfstate-grupo12-fiap-2025"
    key    = "infra/terraform.tfstate"
    region = "sa-east-1"
  }
}

# ECR para armazenar a imagem do projeto
resource "aws_ecr_repository" "project_repo" {
  name = "hackathon_ecr"
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "hackathon-ecs-cluster"
}


# S3 
resource "aws_s3_bucket" "code-bucket" {
  bucket = "hackathon-grupo12-fiap-code-bucket"
}

# S3 Arquivos out
resource "aws_s3_bucket" "files-in-bucket" {
  bucket = "hackathon-grupo12-fiap-files-in-bucket"
}

# S3 Arquivos in
resource "aws_s3_bucket" "files-out-bucket" {
  bucket = "hackathon-grupo12-fiap-files-out-bucket"
}

data "aws_iam_policy_document" "queue_policy" {
  statement {
    effect = "Allow"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["sqs:SendMessage"]
    resources = ["arn:aws:sqs:*:*:sqs_processar_arquivo"]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.files-in-bucket.arn]
    }
  }
}

# SQS processar_arquivo
resource "aws_sqs_queue" "processar_arquivo" {
  name                       = "sqs_processar_arquivo"
  policy                     = data.aws_iam_policy_document.queue_policy.json
  visibility_timeout_seconds = 960
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.processar_arquivo_dlq.arn
    maxReceiveCount     = 5
  })
}

resource "aws_sqs_queue" "processar_arquivo_dlq" {
  name = "sqs_processar_arquivo_dlq"
}

resource "aws_sqs_queue_redrive_allow_policy" "processar_arquivo_dlq_policy" {
  queue_url = aws_sqs_queue.processar_arquivo_dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue",
    sourceQueueArns   = [aws_sqs_queue.processar_arquivo.arn]
  })
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.files-in-bucket.id

  queue {
    queue_arn     = aws_sqs_queue.processar_arquivo.arn
    events        = ["s3:ObjectCreated:*"]
    filter_suffix = ".mp4"
  }
}


# Criação da Tabela DynamoDB
resource "aws_dynamodb_table" "processamento_arquivo" {
  name         = "GerenciadorTable"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S" # Tipo da chave: "S" para string, "N" para número, "B" para binário
  }

  tags = {
    Team = "Grupo12Hackathon"
  }
}

# SQS Notificação
resource "aws_sqs_queue" "sqs_notificacao" {
  name                       = "sqs_notificacao"
  visibility_timeout_seconds = 120
}