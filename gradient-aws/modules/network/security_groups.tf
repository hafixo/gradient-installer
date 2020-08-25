// private
resource "aws_security_group" "private" {
  name        = "${var.name} - private"
  description = "All private subnets"
  vpc_id      = module.vpc.vpc_id

  tags = {
    Name = "${var.name} - private"
  }
}

resource "aws_security_group_rule" "private_allow_all_from_private" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  security_group_id        = aws_security_group.private.id
  source_security_group_id = aws_security_group.private.id
}

resource "aws_security_group_rule" "private_allow_all_to_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 65535
  protocol          = "-1"
  security_group_id = aws_security_group.private.id
  cidr_blocks       = ["0.0.0.0/0"]
}


// public
resource "aws_security_group" "public" {
  name        = "${var.name} - public"
  description = "All public subnets"
  vpc_id      = module.vpc.vpc_id

  tags = {
    Name = "${var.name} - public"
  }
}

resource "aws_security_group_rule" "public_allow_all_from_private" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  security_group_id        = aws_security_group.public.id
  source_security_group_id = aws_security_group.private.id
}

resource "aws_security_group_rule" "public_allow_all_to_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 65535
  protocol          = "-1"
  security_group_id = aws_security_group.public.id
  cidr_blocks       = ["0.0.0.0/0"]
}
