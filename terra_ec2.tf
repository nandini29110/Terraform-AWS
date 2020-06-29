#setup provider
provider "aws" {
  region = "ap-south-1"
  #alias = "infra"
  profile = "terra_user"
}


resource "tls_private_key" "private_key" {
  algorithm   = "RSA"
  rsa_bits = "2048"
  #provider = aws.infra
}

resource "aws_key_pair" "public_key" {
  key_name   = "EC2key"
  public_key = tls_private_key.private_key.public_key_openssh
 #provider   =  aws.infra
}

resource "local_file" "final_key" {
    content     = tls_private_key.private_key.private_key_pem
    filename = "EC2key.pem"
    #provider = aws.infra
}

resource "aws_default_vpc" "default" {
  tags = {
    Name = "Default VPC"
  }
}

resource "aws_security_group" "allow_tls" {
  name        = "allow_tls"
  description = "Allow TLS inbound traffic"
  #provider   =  aws.infra
  ingress {
    description = "TLS from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    
  }
 ingress {
    description = "TLS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
        description = "ping-icmp"
        from_port   = -1
        to_port     = -1
        protocol    = "icmp"
        cidr_blocks = ["0.0.0.0/0"]
    }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_tls"
  }
}

variable "ec2_ami" {
  default = "ami-052c08d70def0ac62"
}


resource "aws_instance"  "my_Ec2_instance" {
  ami           = var.ec2_ami
  instance_type = "t2.micro"
 # provider      = aws.infra
  key_name =  aws_key_pair.public_key.key_name
  security_groups = ["${aws_security_group.allow_tls.name}"]
  # user_data = <<-EOF
  #         #! /bin/bash
  #         sudo yum install httpd -y
  #         sudo systemctl start httpd
  #         sudo systemctl enable httpd
  #         echo "<h1>sample webserver creating using terraform</h1>" >> /var/www/html/index.html
  # EOF
  tags = {
    Name = "webserver"
  }
  #just after launching connect to OS using ssh.

  connection{
    type       = "ssh"
    user       =  "ec2-user"
    private_key =  tls_private_key.private_key.private_key_pem 
    host        = self.public_ip
    port  = 22
  }
  #now as we want to launch a webserver on OS , hence to run the #commands to configure web-server.

  provisioner "remote-exec" {
    inline  = [
      "sudo yum install httpd git -y",
      "sudo systemctl start httpd",
      "sudo systemctl enable httpd",
      "sudo su << EOF",
      "echo '<h1>sample webserver creating using terraform</h1>' >> /var/www/html/index.html",
      "EOF"
    ]
  }
  
}

resource "aws_ebs_volume" "EBS_volume" {
  availability_zone = aws_instance.my_Ec2_instance.availability_zone
  size              = 1
  #provider = aws.infra

  tags = {
    Name = "My_EC2_Volume"
  }
}

resource "aws_volume_attachment" "ebs_att" {
 device_name = "/dev/xvdf"
 volume_id = aws_ebs_volume.EBS_volume.id
 instance_id = aws_instance.my_Ec2_instance.id
}


 resource "null_resource" "null_remote_2"  {
  depends_on = [
    aws_volume_attachment.ebs_att,
  ]

 connection{
    type       = "ssh"
    user       =  "ec2-user"
    private_key =  tls_private_key.private_key.private_key_pem 
    host        = aws_instance.my_Ec2_instance.public_ip
 }
 #provider = aws.infra
 provisioner "remote-exec"{
   inline = [
     "sudo mkfs.ext4 /dev/xvdf",
     "sudo mount /dev/xvdf /var/www/html",
     "sudo rm -rf /var/www/html/*",
    #  "sudo git clone  /var/www/html",
     "sudo git clone https://github.com/nandinish/task1.git /var/www/html "
   ] 
 }

 provisioner "remote-exec" {
        when    = destroy
        inline  = [
            "sudo umount /var/www/html"
        ]
    }
}
output "myoutebs" {
 value = aws_ebs_volume.EBS_volume.id
}

// creating s3 bucket

resource "aws_s3_bucket" "nannubucket" {
  bucket = "nannubuckett1234567890"
  acl    = "public-read"

   tags = {
    Name        = "My bucket"
     Environment = "Dev"
  }
}

// to downoad images form github into our local repo

resource "null_resource" "github_data" {
  provisioner "local-exec" {
    command = "git clone https://github.com/nandinish/abcd.git  bucket_images"
  }

}



// to upload those images into s3 bucket we use aws_s3_bucket_object

resource "aws_s3_bucket_object" "bucket_object" {
  bucket = "nannubuckett1234567890"
  key    = "my_world.jpg"
  source = "bucket_images\\photo.jpg"
  acl    = "public-read"
  //etag = filemd5("C:\\Users\\NANDINI SHARMA\\Desktop\\terraform_code\\terra_code\\bucket_images")
}

// creating cloudfront distribution
# resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
#   comment = "its my cloudfront"
# }

resource "aws_cloudfront_distribution" "s3_distribution" {

  # depends_on = [aws_s3_bucket.nannubucket]

  origin {
    domain_name = aws_s3_bucket.nannubucket.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.nannubucket.id

    # s3_origin_config {
    #   origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
    # }
  }

  enabled             = true
  is_ipv6_enabled     = true
  # comment             = "Some comment"
  # default_root_object = "index.html"

  # logging_config {
  #   include_cookies = false
  #   bucket          = "mylogs.s3.amazonaws.com"
    //prefix          = "myprefix"
  # }

  //aliases = ["mysite.example.com", "yoursite.example.com"]

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.nannubucket.id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    # min_ttl                = 0
    # default_ttl            = 3600
    # max_ttl                = 86400
  }

 
  # price_class = "PriceClass_200"

  restrictions {
    geo_restriction {
      restriction_type = "none"
      # locations        = ["US", "CA", "GB", "DE", "IN"]
    }
  }

  tags = {
    Environment = "production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
  depends_on = [
    aws_s3_bucket.nannubucket
   ]

   connection {
  type = "ssh"
  user = "terra-user"
  private_key = tls_private_key.private_key.private_key_pem
  host = aws_instance.my_Ec2_instance.public_ip
 }
provisioner "remote-exec" {
     
      inline = [
          "sudo su << EOF",
           "echo \"<img src=\"https://\"${aws_cloudfront_distribution.s3_distribution.domain_name}\"/image.jpg\">\" >> /var/www/html/nandini.html",

            "EOF"
      ]
  }
}

}

resource "null_resource" "nulllocal1"  {
    depends_on = [
        aws_cloudfront_distribution.s3_distribution,
     ]

     provisioner "local-exec" {
           "echo \"<img src=\"https://\"${aws_cloudfront_distribution.s3_distribution.domain_name}\"/image.jpg\">\" >> /var/www/html/nandini.html",
           command = "start chrome  ${aws_instance.my_Ec2_instance.public_ip}"
      }
    }
 }
 


