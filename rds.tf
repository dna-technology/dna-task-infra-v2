# Security Group for RDS
resource "aws_security_group" "rds" {
  name        = "${module.this.id}-rds"
  description = "Security group for RDS instance"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow PostgreSQL from ECS tasks"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    module.this.tags,
    {
      Name = "${module.this.id}-rds"
    }
  )
}

# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${module.this.id}-db-subnet"
  subnet_ids = aws_subnet.private[*].id

  tags = merge(
    module.this.tags,
    {
      Name = "${module.this.id}-db-subnet"
    }
  )
}

# RDS Instance
resource "aws_db_instance" "main" {
  identifier     = "${module.this.id}-db"
  engine         = "postgres"
  engine_version = "16.6"
  instance_class = "db.t4g.micro"

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "mon:04:00-mon:05:00"

  skip_final_snapshot       = true
  final_snapshot_identifier = "${module.this.id}-final-snapshot"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = merge(
    module.this.tags,
    {
      Name = "${module.this.id}-db"
    }
  )
}
