resource "null_resource" "join" {
  count       = "${var.count}"
  depends_on  = ["null_resource.install"]

  connection {
    host  = "${element(var.connections, count.index)}"
    user  = "root"
    agent = true
  }

  provisioner "remote-exec" {
    inline = [
      "${var.join_command}"
    ]
  }
}