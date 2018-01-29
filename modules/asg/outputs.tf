output "outbound" {
  value = "${aws_security_group.outbound.id}"
}

output "bastion-ssh" {
  value = "${aws_security_group.bastion-ssh.id}"
}

output "intranet" {
  value = "${aws_security_group.intranet.id}"
}

output "tikv" {
  value = "${aws_security_group.tikv.id}"
}

output "tidb" {
  value = "${aws_security_group.tidb.id}"
}

output "pd" {
  value = "${aws_security_group.pd.id}"
}

output "aws-elb" {
  value = "${aws_security_group.aws-elb.id}"
}
