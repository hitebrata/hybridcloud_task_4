// AWS prvider details

provider "aws" {
   profile = var.profile
   region     = var.aws_region
}
// Create VPC
resource "aws_vpc" "prod_vpc" {
    cidr_block = var.vpc_cidr
    instance_tenancy = var.instanceTenancy
    enable_dns_support = var.dnsSupport
    enable_dns_hostnames = var.dnsHostNames
tags = {
        Name = "prod_vpc"
    }
}
//Create Internet Gateway
resource "aws_internet_gateway" "prod_gateway" {
  depends_on = [aws_vpc.prod_vpc]
    vpc_id = aws_vpc.prod_vpc.id

tags = {
        Name = "ProdGateway"
    }
}

// Public Subnet
resource "aws_subnet" "pub_subnet" {
    depends_on = [aws_vpc.prod_vpc]
    vpc_id = aws_vpc.prod_vpc.id
    cidr_block = var.public_subnet_cidr
    availability_zone = var.pub_availabilityZone
    map_public_ip_on_launch = "true" //it makes this a public subnet

    tags = {
        Name = "Public Subnet"
    }
}
// Private Subnet
resource "aws_subnet" "pvt_subnet" {
    depends_on = [aws_vpc.prod_vpc]
    vpc_id = aws_vpc.prod_vpc.id
    cidr_block = var.private_subnet_cidr
    availability_zone = var.pvt_availabilityZone

    tags = {
        Name = "Private Subnet"
    }
}

// create routing table for IGW
resource "aws_route_table" "igw_routing_table" {
    depends_on = [aws_internet_gateway.prod_gateway]
    vpc_id = aws_vpc.prod_vpc.id
    route{
        cidr_block = "0.0.0.0/0" //associated subnet can reach everywhere
        gateway_id = aws_internet_gateway.prod_gateway.id
       }
}
//aws_route_table_association for IGW
 resource "aws_route_table_association" "igw_route_asction" {
    depends_on = [ aws_subnet.pub_subnet, aws_route_table.igw_routing_table ]
    subnet_id = aws_subnet.pub_subnet.id
    route_table_id = aws_route_table.igw_routing_table.id
}
resource "aws_eip" "myeip" {
  vpc      = true
  depends_on = [aws_internet_gateway.prod_gateway,]

}
// NAT_Gateway
resource "aws_nat_gateway" "nat_gateway" {
  depends_on = [aws_vpc.prod_vpc]
  allocation_id = aws_eip.myeip.id
  subnet_id     = aws_subnet.pub_subnet.id
  tags = {
    Name = "nat gatway"
  }
}
// create routing table for NGW
resource "aws_route_table" "nat_routing_table" {
    depends_on = [aws_vpc.prod_vpc]
    vpc_id = aws_vpc.prod_vpc.id
    route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway.id
  }
    tags = {
        Name = "nat routing table"
    }
}

//aws_route_table_association for NGW
resource "aws_route_table_association" "nat_route_asction" {
    depends_on = [ aws_subnet.pvt_subnet, aws_nat_gateway.nat_gateway ]
    subnet_id = aws_subnet.pvt_subnet.id
    route_table_id = aws_route_table.nat_routing_table.id
}

// SG for Bastion
resource "aws_security_group" "bastion_sg" {
    depends_on = [aws_vpc.prod_vpc]
    name = "bastion-sg"
    description = "Allow ssh inbound traffic"
    vpc_id = aws_vpc.prod_vpc.id
    ingress {
        description = "ssh"
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = var.ingress_cidr
    }
    egress {
        from_port = 0
        to_port = 0
        protocol = -1
        cidr_blocks = var.egress_cidr
    }
    tags = {
    Name = "BastionSG"
    }
}
//SG for Bstion & MySQL
resource "aws_security_group" "bastion_db_sg" {
    depends_on = [aws_vpc.prod_vpc]
    description = "Allow ssh inbound traffic"
    vpc_id = aws_vpc.prod_vpc.id
    ingress {
        description = "ssh"
        from_port = 22
        to_port = 22
        protocol = "tcp"
        security_groups = ["${aws_security_group.bastion_sg.id}"]
    }
    egress {
        from_port = 0
        to_port = 0
        protocol = -1
        cidr_blocks = var.egress_cidr
    }
    tags = {
    Name = "BastionMySQLSG"
    }
}
// SG for Webserver
resource "aws_security_group" "web_sg" {
    depends_on = [aws_vpc.prod_vpc]
    name = "vpc_web"
    description = "Allow incoming http and ssh connections."
    vpc_id = aws_vpc.prod_vpc.id
    ingress {
        description = "ssh"
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = var.ingress_cidr
    }
    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = var.ingress_cidr
}
    ingress {
        from_port = -1
        to_port = -1
        protocol = "icmp"
        cidr_blocks = var.ingress_cidr
    }
    egress { # MySQL
        from_port = 3306
        to_port = 3306
        protocol = "tcp"
        cidr_blocks = var.egress_cidr
    }
    egress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = var.egress_cidr
    }
    egress {
        from_port = 443
        to_port = 443
        protocol = "tcp"
        cidr_blocks = var.egress_cidr
    }

    tags = {
        Name = "WebServerSG"
    }
}
// SG for DataBase
resource "aws_security_group" "db_sg" {
    depends_on = [aws_vpc.prod_vpc]
    name = "vpc_db"
    vpc_id = aws_vpc.prod_vpc.id
    description = "Allow incoming database connections."
    ingress { # MySQL
        from_port = 3306
        to_port = 3306
        protocol = "tcp"
        security_groups = ["${aws_security_group.web_sg.id}"]
    }
    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = var.egress_cidr
    }
    tags = {
        Name = "DBServerSG"
    }
}
//Launch WordPress
resource "aws_instance" "web" {
    depends_on = [aws_security_group.web_sg, aws_subnet.pub_subnet]
    ami = var.wordpressami
    instance_type = var.wpinstance
    key_name = var.aws_key_name
    vpc_security_group_ids = [ aws_security_group.web_sg.id ]
    subnet_id = aws_subnet.pub_subnet.id
    associate_public_ip_address = true
    user_data = <<EOF
#!/bin/bash
sudo yum update -y
sudo yum -y install http://rpms.remirepo.net/enterprise/remi-release-7.rpm
sudo yum install yum-utils -y
sudo yum-config-manager --enable remi-php72
sudo amazon-linux-extras install lamp-mariadb10.2-php7.2 -y
sudo yum install httpd  -y
sudo systemctl start httpd
sudo systemctl enable httpd
sudo wget http://wordpress.org/latest.tar.gz
sudo tar -xvzf latest.tar.gz -C /var/www/html
sudo chown -R apache /var/www/html/wordpress
sudo cat >> /etc/httpd/conf/httpd.conf << EOL
<VirtualHost *:80>
ServerAdmin tecmint@tecmint.com
DocumentRoot /var/www/html/wordpress
ServerName tecminttest.com
ServerAlias www.tecminttest.com
ErrorLog /var/log/httpd/tecminttest-error-log
CustomLog /var/log/httpd/tecminttest-acces-log common
</VirtualHost>
EOL
sudo systemctl restart httpd
EOF
    tags = {
        Name = "Web Server"
    }
}
//Launch MySQL database
resource "aws_instance" "db" {
    depends_on = [aws_security_group.db_sg, aws_subnet.pvt_subnet]
    ami = var.mysqlami
    instance_type = var.mysqlinstance
    key_name = var.aws_key_name
    vpc_security_group_ids = [ aws_security_group.db_sg.id, aws_security_group.bastion_db_sg.id ]
    subnet_id = aws_subnet.pvt_subnet.id
    tags = {
        Name = "DB Server 1"
    }
}
//Launch bastion host
resource "aws_instance" "bastion" {
    depends_on = [ aws_security_group.bastion_sg, aws_subnet.pub_subnet ]
    ami = var.amis
    instance_type = var.bastioninstance
    key_name = var.aws_key_name
    vpc_security_group_ids = [ aws_security_group.bastion_sg.id ]
    subnet_id = aws_subnet.pub_subnet.id
    associate_public_ip_address = true
    tags = {
        Name = "BastionHost"
    }
}
