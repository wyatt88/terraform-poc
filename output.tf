output "bastion_ip" {
  value = "${join("\n", aws_instance.bastion.*.public_ip)}"
}

output "tidb" {
  value = "${join("\n", aws_instance.tidb.*.private_ip)}"
}

output "tikv" {
  value = "${join("\n", aws_instance.tikv.*.private_ip)}"
}

output "pd" {
  value = "${join("\n", aws_instance.pd.*.private_ip)}"
}

output "monitor" {
  value = "${join("\n", aws_instance.monitor.*.private_ip)}"
}

output "inventory" {
  value = "${data.template_file.inventory.rendered}"
}
