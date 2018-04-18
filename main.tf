provider "aws" {
  access_key             = "${var.aws_access_key}"
  secret_key             = "${var.aws_secret_key}"
  region                 = "${var.aws_region}"
  skip_region_validation = true
}

data "aws_availability_zones" "available" {}

module "aws-vpc" {
  source             = "modules/vpc"
  azs                = "${data.aws_availability_zones.available.names}"
  public_subnets     = "${var.public_subnets}"
  private_subnets    = "${var.private_subnets}"
  vpc_cidr_block     = "${var.vpc_cidr_block}"
  enable_nat_gateway = "${var.enable_nat_gateway}"
  single_nat_gateway = "${var.single_nat_gateway}"
}

module "aws-elb" {
  source            = "modules/elb"
  instance_ids      = "${aws_instance.tidb.*.id}"
  subnet_public_ids = "${module.aws-vpc.aws_subnet_ids_public}"
  asg_elb_sql_id    = "${module.aws-asg.aws-elb}"
}

module "aws-asg" {
  source     = "modules/asg"
  aws_vpc_id = "${module.aws-vpc.aws_vpc_id}"
}

module "ssh-key" {
  source = "modules/sshkey"
}

data "aws_ami" "distro" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["137112412989"] #Amazon Linux 2
}

resource "aws_instance" "bastion" {
  count                  = 1
  ami                    = "${data.aws_ami.distro.id}"
  instance_type          = "t2.micro"
  subnet_id              = "${element(module.aws-vpc.aws_subnet_ids_public, 0)}"
  key_name               = "${module.ssh-key.key_name}"
  vpc_security_group_ids = ["${module.aws-asg.bastion-ssh}", "${module.aws-asg.outbound}"]

  tags {
    Name = "PingCAP-Bastion-${count.index}"
  }
}

resource "null_resource" "bastion" {
  # Changes to any instance of the bastion requires re-provisioning
  triggers {
    bastion_instance_ids = "${join(",",aws_instance.bastion.*.id)}"
  }

  provisioner "file" {
    source      = "keys/private.pem"
    destination = "/home/ec2-user/.ssh/aws.key"

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = "${module.ssh-key.private_key_pem}"
      host        = "${aws_eip.bastion.public_ip}"
    }
  }
}

resource "null_resource" "bastion-chmod" {
  # Changes to any instance of the bastion requires re-provisioning
  triggers {
    bastion_instance_ids = "${join(",",aws_instance.bastion.*.id)}"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 600 /home/ec2-user/.ssh/aws.key",
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = "${module.ssh-key.private_key_pem}"
      host        = "${aws_eip.bastion.public_ip}"
    }
  }
}

resource "aws_instance" "tidb" {
  count                  = "${var.tidb_count}"
  ami                    = "${data.aws_ami.distro.id}"
  instance_type          = "${var.tidb_instance_type_map[var.tidb_instance_type_number]}"
  subnet_id              = "${element(module.aws-vpc.aws_subnet_ids_private, count.index)}"
  key_name               = "${module.ssh-key.key_name}"
  vpc_security_group_ids = ["${module.aws-asg.intranet}", "${module.aws-asg.outbound}", "${module.aws-asg.tidb}"]

  tags {
    Name    = "PingCAP-TiDB-${count.index}"
    Cluster = "PingCAP-TiDB-Cluster"
    Role    = "TiDB-Server"
  }
}

resource "aws_instance" "tikv" {
  count                  = "${var.tikv_count}"
  ami                    = "${data.aws_ami.distro.id}"
  instance_type          = "${var.tidb_instance_type_map[var.tikv_instance_type_number]}"
  subnet_id              = "${element(module.aws-vpc.aws_subnet_ids_private, count.index)}"
  key_name               = "${module.ssh-key.key_name}"
  vpc_security_group_ids = ["${module.aws-asg.intranet}", "${module.aws-asg.outbound}", "${module.aws-asg.tikv}"]

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
  instance_type          = "${var.tidb_instance_type_map[var.pd_instance_type_number]}"
  subnet_id              = "${element(module.aws-vpc.aws_subnet_ids_private, count.index)}"
  key_name               = "${module.ssh-key.key_name}"
  vpc_security_group_ids = ["${module.aws-asg.intranet}", "${module.aws-asg.outbound}", "${module.aws-asg.pd}"]

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
  subnet_id              = "${element(module.aws-vpc.aws_subnet_ids_private, count.index)}"
  key_name               = "${module.ssh-key.key_name}"
  vpc_security_group_ids = ["${module.aws-asg.intranet}", "${module.aws-asg.outbound}"]

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

#terraform {
#  backend "consul" {
#    address = "127.0.0.1:32770"
#    path    = "tidb-cluster"
#    lock    = false
#  }
#}

