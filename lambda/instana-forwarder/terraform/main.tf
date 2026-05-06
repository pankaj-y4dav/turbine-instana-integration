# ──────────────────────────────────────────────
# S3 backup bucket (Firehose requires a backup destination)
# ──────────────────────────────────────────────
resource "aws_s3_bucket" "firehose_backup" {
  bucket = var.backup_bucket_name
}

resource "aws_s3_bucket_lifecycle_configuration" "backup_expiry" {
  bucket = aws_s3_bucket.firehose_backup.id
  rule {
    id     = "expire-old-logs"
    status = "Enabled"
    expiration { days = var.backup_retention_days }
  }
}

resource "aws_s3_bucket_public_access_block" "firehose_backup" {
  bucket                  = aws_s3_bucket.firehose_backup.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ──────────────────────────────────────────────
# Lambda batch processor (invoked by Firehose per batch, not per event)
# Transforms CWL format → Instana format and forwards via HTTP
# ──────────────────────────────────────────────
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "processor" {
  name               = "instana-firehose-processor"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "processor_basic" {
  role       = aws_iam_role.processor.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "processor" {
  function_name    = "instana-firehose-processor"
  role             = aws_iam_role.processor.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = "${path.module}/../processor.zip"
  source_code_hash = filebase64sha256("${path.module}/../processor.zip")
  timeout          = 60

  environment {
    variables = {
      INSTANA_BASE_URL = var.instana_base_url
      INSTANA_API_KEY  = var.instana_api_key
      LOG_SERVICE_NAME = var.log_service_name
    }
  }
}

# ──────────────────────────────────────────────
# IAM role for Firehose
# ──────────────────────────────────────────────
data "aws_iam_policy_document" "firehose_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "firehose" {
  name               = "instana-firehose-role"
  assume_role_policy = data.aws_iam_policy_document.firehose_assume.json
}

data "aws_iam_policy_document" "firehose_policy" {
  statement {
    actions = [
      "s3:PutObject",
      "s3:GetBucketLocation",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.firehose_backup.arn,
      "${aws_s3_bucket.firehose_backup.arn}/*",
    ]
  }
  statement {
    actions   = ["lambda:InvokeFunction"]
    resources = [
      aws_lambda_function.processor.arn,
      "${aws_lambda_function.processor.arn}:*",
    ]
  }
}

resource "aws_iam_role_policy" "firehose" {
  name   = "instana-firehose-policy"
  role   = aws_iam_role.firehose.id
  policy = data.aws_iam_policy_document.firehose_policy.json
}

# ──────────────────────────────────────────────
# Kinesis Firehose delivery stream
# Buffers logs, invokes Lambda processor per batch, backs up to S3
# ──────────────────────────────────────────────
resource "aws_kinesis_firehose_delivery_stream" "instana" {
  name        = "instana-log-forwarder"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn            = aws_iam_role.firehose.arn
    bucket_arn          = aws_s3_bucket.firehose_backup.arn
    buffering_size      = 5    # MB
    buffering_interval  = 60   # seconds
    compression_format  = "GZIP"
    prefix              = "instana-logs/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "instana-logs-errors/!{firehose:error-output-type}/year=!{timestamp:yyyy}/month=!{timestamp:MM}/"

    processing_configuration {
      enabled = true
      processors {
        type = "Lambda"
        parameters {
          parameter_name  = "LambdaArn"
          parameter_value = "${aws_lambda_function.processor.arn}:$LATEST"
        }
        parameters {
          parameter_name  = "BufferSizeInMBs"
          parameter_value = "3"
        }
        parameters {
          parameter_name  = "BufferIntervalInSeconds"
          parameter_value = "60"
        }
      }
    }
  }
}

resource "aws_lambda_permission" "firehose_invoke" {
  statement_id  = "firehose-invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.processor.function_name
  principal     = "firehose.amazonaws.com"
  source_arn    = aws_kinesis_firehose_delivery_stream.instana.arn
}

# ──────────────────────────────────────────────
# IAM role for CloudWatch Logs → Firehose
# ──────────────────────────────────────────────
data "aws_iam_policy_document" "cwl_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cwl_to_firehose" {
  name               = "instana-cwl-to-firehose"
  assume_role_policy = data.aws_iam_policy_document.cwl_assume.json
}

data "aws_iam_policy_document" "cwl_to_firehose_policy" {
  statement {
    actions   = ["firehose:PutRecord", "firehose:PutRecordBatch"]
    resources = [aws_kinesis_firehose_delivery_stream.instana.arn]
  }
}

resource "aws_iam_role_policy" "cwl_to_firehose" {
  name   = "instana-cwl-firehose-policy"
  role   = aws_iam_role.cwl_to_firehose.id
  policy = data.aws_iam_policy_document.cwl_to_firehose_policy.json
}

# ──────────────────────────────────────────────
# CloudWatch Logs subscription filter → Firehose
# ──────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "source" {
  name              = var.cloudwatch_log_group_name
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_subscription_filter" "instana" {
  name            = "instana-forwarder"
  log_group_name  = aws_cloudwatch_log_group.source.name
  filter_pattern  = var.filter_pattern
  destination_arn = aws_kinesis_firehose_delivery_stream.instana.arn
  role_arn        = aws_iam_role.cwl_to_firehose.arn
  depends_on      = [aws_cloudwatch_log_group.source]
}
