terraform {
  backend "s3" {
    bucket = "sm-bucket-evaluacion"
    key    = "states/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region  = "us-east-1"
  profile = "test"
}

resource "aws_s3_bucket" "sm_bucket" {
  bucket = "sm-bucket-evaluacion"

  lifecycle_rule {
    id      = "log"
    enabled = true

    expiration {
      days = 30
    }
  }

  tags = {
    username = "smejia"
  }
}

resource "aws_s3_bucket_object" "outputs_folder" {
  bucket = aws_s3_bucket.sm_bucket.bucket
  key    = "outputs/"

  tags = {
    username = "smejia"
  }
}


resource "aws_iam_role" "ec2_role" {
  name = "ec2_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

  tags = {
    username = "smejia"
  }
}

resource "aws_iam_role_policy" "ec2_role_policy" {
  name = "ec2_role_policy"
  role = aws_iam_role.ec2_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject"
      ],
      "Resource": "arn:aws:s3:::sm-bucket-evaluacion/*"
    }
  ]
}
EOF

}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "ec2_instance_profile"
  role = aws_iam_role.ec2_role.name

  tags = {
    username = "smejia"
  }
}

resource "aws_key_pair" "my_key_pair" {
  key_name   = "key-sm"
  public_key = file("/home/santiago/.ssh/id_rsa.pub")

  tags = {
    username = "smejia"
  }
}

resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name     = "vpc_evalua_SM",
    username = "smejia"
  }
}

resource "aws_subnet" "subnet1" {
  vpc_id     = aws_vpc.my_vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false

  tags = {
    Name     = "subnet_evalu_SM1",
    username = "smejia"
  }
}

resource "aws_security_group" "my_security_group" {
  name        = "evalucion_sm"
  description = "Reglas de seguridad para la instancia EC2"
  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    username = "smejia"
  }
}

resource "aws_instance" "terraform-example" {
  ami           = "ami-012485deee5681dc0"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.subnet1.id
  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y awscli

              while true; do
                private_ip=$(curl http://169.254.169.254/latest/meta-data/local-ipv4)
                timestamp=$(date +"%Y%m%d%H%M%S")
                echo $private_ip > /tmp/private_ip_$timestamp.txt
                aws s3 cp /tmp/private_ip_$timestamp.txt s3://sm-bucket-evaluacion/outputs/private_ip_$timestamp.txt
                sleep 300
              done
              EOF

  tags = {
    Name     = "evaluacion_sm"
    username = "smejia"
  }

  key_name              = aws_key_pair.my_key_pair.key_name
  security_groups       = [aws_security_group.my_security_group.id]
  associate_public_ip_address = true
  iam_instance_profile  = aws_iam_instance_profile.ec2_instance_profile.name
}

resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    username = "smejia"
  }
}

resource "aws_route_table" "route_table" {
  vpc_id = aws_vpc.my_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_igw.id
  }

  tags = {
    Name     = "route-tables-sm"
    username = "smejia"
  }
}

resource "aws_route_table_association" "my_subnet_association" {
  subnet_id      = aws_subnet.subnet1.id
  route_table_id = aws_route_table.route_table.id
}

resource "aws_cloudwatch_log_group" "my_log_group" {
  name              = "/aws/ec2/terraform-example"
  retention_in_days = 14

  tags = {
    username = "smejia"
  }
}

resource "aws_cloudwatch_log_stream" "my_log_stream" {
  name           = "example-log-stream"
  log_group_name = aws_cloudwatch_log_group.my_log_group.name

}

###----------------------HASTA ACA VAMOS BIEN objetivo de la prueba--------------------
#--- creo la segunda subnet y el balanceador de carga-------------

resource "aws_subnet" "subnet2" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = false

  tags = {
    Name     = "subnet_evalu_SM2"
    username = "smejia"
  }
}

resource "aws_lb" "load_balancer" {
name               = "sm-load-balancer"
internal           = false
load_balancer_type = "application"
security_groups    = [aws_security_group.my_security_group.id]
subnets            = [aws_subnet.subnet1.id, aws_subnet.subnet2.id]

tags = {
Name     = "sm-load-balancer"
username = "smejia"
  }
}

resource "aws_lb_listener" "http" {
load_balancer_arn = aws_lb.load_balancer.arn
port              = "80"
protocol          = "HTTP"

default_action {
type             = "forward"
target_group_arn = aws_lb_target_group.my_target_group.arn
}

tags = {
Name     = "sm-lb-listener"
username = "smejia"
}
}

resource "aws_lb_target_group" "my_target_group" {
name     = "sm-target-group"
port     = 80
protocol = "HTTP"
vpc_id   = aws_vpc.my_vpc.id

health_check {
path                = "/"
interval            = 30
timeout             = 5
healthy_threshold   = 2
unhealthy_threshold = 2
matcher             = "200"
}

tags = {
Name     = "sm-target-group"
username = "smejia"
}
}

resource "aws_lb_target_group_attachment" "ec2_attachment" {
target_group_arn = aws_lb_target_group.my_target_group.arn
target_id        = aws_instance.terraform-example.id
port             = 80
}

#####---------------cognito, api gw y lambda-----------------------------

resource "aws_cognito_user_pool" "avaluacion_sm" {
  name = "avaluacion_sm_user_pool"
}

resource "aws_cognito_user_pool_client" "avaluacion_sm" {
  user_pool_id = aws_cognito_user_pool.avaluacion_sm.id
  name         = "avaluacion_sm_client"
}

resource "aws_cognito_user_pool_domain" "avaluacion_sm" {
  domain       = "avaluacion-sm-domain"
  user_pool_id = aws_cognito_user_pool.avaluacion_sm.id
}

resource "aws_apigatewayv2_authorizer" "avaluacion_sm" {
  api_id           = aws_apigatewayv2_api.avaluacion_sm.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "avaluacion_sm_authorizer"

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.avaluacion_sm.id]
    issuer   = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.avaluacion_sm.id}"
  }
}

resource "aws_lambda_function" "avaluacion_sm" {
  function_name = "avaluacion_sm_function"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"  # Actualizado a nodejs20.x

  filename      = "${path.module}/lambda_function_payload.zip"

  source_code_hash = filebase64sha256("${path.module}/lambda_function_payload.zip")
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_exec_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_apigatewayv2_api" "avaluacion_sm" {
  name          = "avaluacion_sm_api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_route" "avaluacion_sm" {
  api_id    = aws_apigatewayv2_api.avaluacion_sm.id
  route_key = "GET /avaluacion_sm"

  authorization_type     = "JWT"
  authorizer_id          = aws_apigatewayv2_authorizer.avaluacion_sm.id
  target                 = "integrations/${aws_apigatewayv2_integration.avaluacion_sm.id}"
}

resource "aws_apigatewayv2_integration" "avaluacion_sm" {
  api_id           = aws_apigatewayv2_api.avaluacion_sm.id
  integration_type = "AWS_PROXY"
  integration_uri  = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.avaluacion_sm.arn}/invocations"
}