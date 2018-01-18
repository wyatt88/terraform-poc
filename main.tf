provider "aws" {
  access_key             = "${var.aws_access_key}"
  secret_key             = "${var.aws_secret_key}"
  region                 = "${var.aws_region}"
  skip_region_validation = true
}

locals {
  private_key_filename = "keys/private.pem"
  public_key_filename  = "keys/public.pem"
}

resource "aws_vpc" "vpc_tidb_cluster" {
  cidr_block = "${var.vpc_cidr_block}"

  tags {
    Name = "VPC-TiDB-Cluster"
  }
}

resource "aws_internet_gateway" "vpc_tidb_igw" {
  count  = "${length(var.public_subnets) > 0 ? 1 : 0}"
  vpc_id = "${aws_vpc.vpc_tidb_cluster.id}"
}

resource "aws_eip" "nat" {
  count = "${var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : length(var.azs)) : 0}"
}

resource "aws_nat_gateway" "vpc_tidb_ngw" {
  count = "${var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : length(var.azs)) : 0}"

  allocation_id = "${element(aws_eip.nat.*.id, (var.single_nat_gateway ? 0 : count.index))}"
  subnet_id     = "${element(aws_subnet.public.*.id, (var.single_nat_gateway ? 0 : count.index))}"

  # vpc_id        = "${aws_vpc.vpc_tidb_cluster.id}"

  depends_on = ["aws_internet_gateway.vpc_tidb_igw"]
}

resource "aws_subnet" "public" {
  vpc_id            = "${aws_vpc.vpc_tidb_cluster.id}"
  count             = "${length(var.azs)}"
  availability_zone = "${element(var.azs,count.index)}"
  cidr_block        = "${element(var.public_subnets,count.index)}"

  tags {
    Name = "Public-Subnet-TiDB"
    Tier = "Public"
  }
}

resource "aws_subnet" "private" {
  vpc_id            = "${aws_vpc.vpc_tidb_cluster.id}"
  count             = "${length(var.azs)}"
  availability_zone = "${element(var.azs,count.index)}"
  cidr_block        = "${element(var.private_subnets,count.index)}"

  tags {
    Name = "Private-Subnet-TiDB"
    Tier = "Private"
  }
}

resource "aws_route_table" "public" {
  count = "${length(var.public_subnets) > 0 ? 1 : 0}"

  vpc_id = "${aws_vpc.vpc_tidb_cluster.id}"
}

resource "aws_route" "public_internet" {
  count                  = "${length(var.public_subnets) > 0 ? 1 : 0}"
  route_table_id         = "${aws_route_table.public.id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.vpc_tidb_igw.id}"
}

resource "aws_route_table_association" "public" {
  count          = "${length(var.public_subnets)}"
  subnet_id      = "${element(aws_subnet.public.*.id,count.index)}"
  route_table_id = "${aws_route_table.public.id}"
}

resource "aws_route_table" "private" {
  count = 1

  vpc_id = "${aws_vpc.vpc_tidb_cluster.id}"
}

resource "aws_route" "private_nat_gateway" {
  count = 1

  route_table_id         = "${element(aws_route_table.private.*.id, count.index)}"
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = "${element(aws_nat_gateway.vpc_tidb_ngw.*.id, count.index)}"
}

resource "aws_route_table_association" "private" {
  count          = "${length(var.private_subnets)}"
  subnet_id      = "${element(aws_subnet.private.*.id,count.index)}"
  route_table_id = "${aws_route_table.private.id}"
}

data "aws_ami" "distro" {
  most_recent = true

  filter {
    name   = "name"
    values = ["CentOS7_Marketplace_*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["741251161495"] #CentOS
}

resource "aws_instance" "bastion" {
  count                  = 1
  ami                    = "${data.aws_ami.distro.id}"
  instance_type          = "t2.micro"
  subnet_id              = "${element(aws_subnet.public.*.id, 0)}"
  key_name               = "${aws_key_pair.generated.key_name}"
  vpc_security_group_ids = ["${aws_security_group.bastion-ssh.id}", "${aws_security_group.outbound.id}"]

  tags {
    Name = "PingCAP-Bastion-${count.index}"
  }
}

resource "null_resource" "bastion" {
  # Changes to any instance of the bastion requires re-provisioning
  triggers {
    bastion_instance_ids = "${join(",",aws_instance.bastion.*.id)}"
  }

  connection {
    type        = "ssh"
    user        = "centos"
    private_key = "${tls_private_key.pingcap-generated.private_key_pem}"
    host        = "${aws_instance.bastion.*.public_ip}"
  }

  provisioner "file" {
    source      = "keys/private.pem"
    destination = "/home/centos/.ssh/private.pem"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 600 /home/centos/.ssh/private.pem",
    ]
  }
}

# resource "aws_key_pair" "pingcap" {}

resource "aws_instance" "tidb" {
  count                  = "${var.tidb_count}"
  ami                    = "${data.aws_ami.distro.id}"
  instance_type          = "t2.micro"
  subnet_id              = "${element(aws_subnet.private.*.id, count.index)}"
  key_name               = "${aws_key_pair.generated.key_name}"
  vpc_security_group_ids = ["${aws_security_group.intranet.id}", "${aws_security_group.outbound.id}", "${aws_security_group.tidb.id}"]

  tags {
    Name    = "PingCAP-TiDB-${count.index}"
    Cluster = "PingCAP-TiDB-Cluster"
    Role    = "TiDB-Server"
  }
}

resource "aws_instance" "tikv" {
  count                  = "${var.tikv_count}"
  ami                    = "${data.aws_ami.distro.id}"
  instance_type          = "i3.4xlarge"
  subnet_id              = "${element(aws_subnet.private.*.id, count.index)}"
  key_name               = "${aws_key_pair.generated.key_name}"
  vpc_security_group_ids = ["${aws_security_group.intranet.id}", "${aws_security_group.outbound.id}", "${aws_security_group.tikv.id}"]

  ephemeral_block_device {
    device_name  = "/dev/sdb"
    virtual_name = "ephemeral0"
  }

  ephemeral_block_device {
    device_name  = "/dev/sdc"
    virtual_name = "ephemeral1"
  }

  tags {
    Name    = "PingCAP-TiKV-${count.index}"
    Cluster = "PingCAP-TiKV-Cluster"
    Role    = "TiKV-Server"
  }
}

resource "aws_instance" "pd" {
  count                  = "${var.pd_count}"
  ami                    = "${data.aws_ami.distro.id}"
  instance_type          = "i3.2xlarge"
  subnet_id              = "${element(aws_subnet.private.*.id, count.index)}"
  key_name               = "${aws_key_pair.generated.key_name}"
  vpc_security_group_ids = ["${aws_security_group.intranet.id}", "${aws_security_group.outbound.id}", "${aws_security_group.pd.id}"]

  ephemeral_block_device {
    device_name  = "/dev/sdb"
    virtual_name = "ephemeral0"
  }

  tags {
    Name    = "PingCAP-PD-${count.index}"
    Cluster = "PingCAP-PD-Cluster"
    Role    = "PD-Sever"
  }
}

resource "aws_instance" "monitor" {
  count                  = "${var.monitor_count}"
  ami                    = "${data.aws_ami.distro.id}"
  instance_type          = "t2.micro"
  subnet_id              = "${element(aws_subnet.private.*.id, count.index)}"
  key_name               = "${aws_key_pair.generated.key_name}"
  vpc_security_group_ids = ["${aws_security_group.intranet.id}", "${aws_security_group.outbound.id}"]

  tags {
    Name    = "PingCAP-Monitor-${count.index}"
    Cluster = "PingCAP-Monitor-Cluster"
    Role    = "Monitoring-Server"
  }
}

resource "aws_eip" "bastion" {
  count = 1
}

resource "aws_eip_association" "eip_assoc" {
  instance_id   = "${aws_instance.bastion.id}"
  allocation_id = "${aws_eip.bastion.id}"
}

resource "tls_private_key" "pingcap-generated" {
  count = 1

  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_key_pair" "generated" {
  count      = 1
  depends_on = ["tls_private_key.pingcap-generated"]
  key_name   = "pingcap-generated"
  public_key = "${tls_private_key.pingcap-generated.public_key_openssh}"
}

resource "local_file" "public_key_openssh" {
  count      = 1
  depends_on = ["tls_private_key.pingcap-generated"]
  content    = "${tls_private_key.pingcap-generated.public_key_openssh}"
  filename   = "${local.public_key_filename}"
}

resource "local_file" "private_key_pem" {
  count      = 1
  depends_on = ["tls_private_key.pingcap-generated"]
  content    = "${tls_private_key.pingcap-generated.private_key_pem}"
  filename   = "${local.private_key_filename}"
}

resource "aws_security_group" "bastion-ssh" {
  name   = "pingcap-tidb-ssh-securitygroup"
  vpc_id = "${aws_vpc.vpc_tidb_cluster.id}"

  tags {
    Name = "pingcap-tidb-ssh-securitygroup"
  }
}

resource "aws_security_group_rule" "allow-ssh-connections" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "TCP"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.bastion-ssh.id}"
}

resource "aws_security_group" "outbound" {
  name   = "pingcap-tidb-outbound-securitygroup"
  vpc_id = "${aws_vpc.vpc_tidb_cluster.id}"

  tags {
    Name = "pingcap-tidb-outbound-securitygroup"
  }
}

resource "aws_security_group_rule" "allow-all-out-traffic" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "ALL"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.outbound.id}"
}

resource "aws_security_group" "tidb" {
  name   = "pingcap-tidb-tidb-securitygroup"
  vpc_id = "${aws_vpc.vpc_tidb_cluster.id}"

  tags {
    Name = "pingcap-tidb-tidb-securitygroup"
  }
}

resource "aws_security_group_rule" "allow-tidb-4000-connections" {
  type              = "ingress"
  from_port         = 0
  to_port           = 4000
  protocol          = "TCP"
  cidr_blocks       = ["10.0.0.0/16"]
  security_group_id = "${aws_security_group.tidb.id}"
}

resource "aws_security_group_rule" "allow-tidb-10080-connections" {
  type              = "ingress"
  from_port         = 0
  to_port           = 10080
  protocol          = "TCP"
  cidr_blocks       = ["10.0.0.0/16"]
  security_group_id = "${aws_security_group.tidb.id}"
}

resource "aws_security_group" "tikv" {
  name   = "pingcap-tidb-tikv-securitygroup"
  vpc_id = "${aws_vpc.vpc_tidb_cluster.id}"

  tags {
    Name = "pingcap-tidb-tikv-securitygroup"
  }
}

resource "aws_security_group_rule" "allow-tikv-20160-connections" {
  type              = "ingress"
  from_port         = 0
  to_port           = 20160
  protocol          = "TCP"
  cidr_blocks       = ["10.0.0.0/16"]
  security_group_id = "${aws_security_group.tikv.id}"
}

resource "aws_security_group" "pd" {
  name   = "pingcap-tidb-pd-securitygroup"
  vpc_id = "${aws_vpc.vpc_tidb_cluster.id}"

  tags {
    Name = "pingcap-tidb-pd-securitygroup"
  }
}

resource "aws_security_group_rule" "allow-pd-use-connections" {
  type              = "ingress"
  from_port         = 0
  to_port           = 2379
  protocol          = "TCP"
  cidr_blocks       = ["10.0.0.0/16"]
  security_group_id = "${aws_security_group.pd.id}"
}

resource "aws_security_group_rule" "allow-pd-peer-connections" {
  type              = "ingress"
  from_port         = 0
  to_port           = 2380
  protocol          = "TCP"
  cidr_blocks       = ["10.0.0.0/16"]
  security_group_id = "${aws_security_group.pd.id}"
}

resource "aws_security_group" "monitor" {
  name   = "pingcap-tidb-monitor-securitygroup"
  vpc_id = "${aws_vpc.vpc_tidb_cluster.id}"

  tags {
    Name = "pingcap-tidb-monitor-securitygroup"
  }
}

resource "aws_security_group_rule" "allow-monitor-prometheus-connections" {
  type              = "ingress"
  from_port         = 0
  to_port           = 9090
  protocol          = "TCP"
  cidr_blocks       = ["10.0.0.0/16"]
  security_group_id = "${aws_security_group.monitor.id}"
}

resource "aws_security_group_rule" "allow-monitor-pushgateway-connections" {
  type              = "ingress"
  from_port         = 0
  to_port           = 9091
  protocol          = "TCP"
  cidr_blocks       = ["10.0.0.0/16"]
  security_group_id = "${aws_security_group.monitor.id}"
}

resource "aws_security_group_rule" "allow-monitor-node-connections" {
  type              = "ingress"
  from_port         = 0
  to_port           = 9100
  protocol          = "TCP"
  cidr_blocks       = ["10.0.0.0/16"]
  security_group_id = "${aws_security_group.monitor.id}"
}

resource "aws_security_group_rule" "allow-monitor-grafana-connections" {
  type              = "ingress"
  from_port         = 0
  to_port           = 3000
  protocol          = "TCP"
  cidr_blocks       = ["10.0.0.0/16"]
  security_group_id = "${aws_security_group.monitor.id}"
}

resource "aws_security_group" "intranet" {
  name   = "pingcap-tidb-intranet-securitygroup"
  vpc_id = "${aws_vpc.vpc_tidb_cluster.id}"

  tags {
    Name = "pingcap-tidb-intranet-securitygroup"
  }
}

resource "aws_security_group_rule" "allow-intranet-ssh-connections" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "TCP"
  cidr_blocks       = ["10.0.0.0/16"]
  security_group_id = "${aws_security_group.intranet.id}"
}

resource "aws_security_group_rule" "allow-intranet-icmp-connections" {
  type              = "ingress"
  from_port         = 8
  to_port           = 0
  protocol          = "ICMP"
  cidr_blocks       = ["10.0.0.0/16"]
  security_group_id = "${aws_security_group.intranet.id}"
}

resource "aws_security_group" "aws-elb" {
  name   = "pingcap-tidb-sql-securitygroup-elb"
  vpc_id = "${aws_vpc.vpc_tidb_cluster.id}"

  tags {
    Name = "pingcap-tidb-sql-securitygroup-elb"
  }
}

resource "aws_security_group_rule" "aws-allow-tidb-access" {
  type              = "ingress"
  from_port         = 0
  to_port           = 4000
  protocol          = "TCP"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.aws-elb.id}"
}

resource "aws_security_group_rule" "aws-allow-sql-egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "ALL"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.aws-elb.id}"
}

resource "aws_elb" "aws-elb-sql" {
  name            = "pingcap-tidb-sql-elb"
  subnets         = ["${aws_subnet.public.*.id}"]
  security_groups = ["${aws_security_group.aws-elb.id}"]

  listener {
    instance_port     = 4000
    instance_protocol = "tcp"
    lb_port           = 4000
    lb_protocol       = "tcp"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "TCP:4000"
    interval            = 30
  }

  instances                   = ["${aws_instance.tidb.*.id}"]
  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags {
    Name = "pingcap-tidb-sql-elb"
  }
}

data "template_file" "inventory" {
  template = "${file("${path.module}/templates/inventory.tpl")}"

  vars {
    list_tidb    = "${join("\n",aws_instance.tidb.*.private_ip)}"
    list_tikv    = "${join("\n",aws_instance.tikv.*.private_ip)}"
    list_pd      = "${join("\n",aws_instance.pd.*.private_ip)}"
    list_monitor = "${join("\n",aws_instance.monitor.*.private_ip)}"
  }
}

resource "null_resource" "inventories" {
  provisioner "local-exec" {
    command = "echo '${data.template_file.inventory.rendered}' > ./inventory.ini"
  }

  triggers {
    template = "${data.template_file.inventory.rendered}"
  }
}

terraform {
  backend "consul" {
    address = "127.0.0.1:32772"
    path    = "tidb-cluster"
    lock    = false
  }
}
