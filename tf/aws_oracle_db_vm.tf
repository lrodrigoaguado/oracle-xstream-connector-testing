
# Optional: Define a variable for mapping AMIs to the correct SSH user
variable "ssh_user" {
  description = "SSH user based on AMI type"
  type        = map(string)
  default     = {
    # Amazon Linux
    "ami-0c55b159cbfafe1f0" = "ec2-user"
    # Ubuntu
    "ami-0885b1f6bd170450c" = "ubuntu"
    # RHEL
    "ami-0b0af3577fe5e3532" = "ec2-user"
    # Debian
    "ami-0bd9223868b4778d7" = "admin"
    # CentOS
    "ami-0f2b4fc905b0bd1f1" = "centos"
    # Oracle Linux
    "ami-07af4f1c7eb1971ff" = "ec2-user"
  }
}
# Security group for EC2 instance
resource "aws_security_group" "allow_ssh_oracle" {
  name        = "${var.prefix}_allow_ssh_oracle"
  description = "Allow SSH and Oracle inbound traffic"
  vpc_id      = aws_vpc.main.id
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Oracle SQL*Net access"
    from_port   = 1521
    to_port     = 1521
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Oracle EM Express access"
    from_port   = 5500
    to_port     = 5500
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
    Name = "${var.prefix}-oracle-sg"
  }
}


data "aws_ami" "oracle_ami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# EC2 instance for Oracle
# /var/log/cloud-init.log
# /var/log/cloud-init-output.log
# /var/lib/cloud/instances/i-0c42e1665ff8e11f2/user-data.txt
# sudo cat /var/lib/cloud/instance/scripts/part-001
resource "aws_instance" "oracle_instance" {
  ami = data.aws_ami.oracle_ami.id
  instance_type = "t3.large"
  key_name      = aws_key_pair.tf_key.key_name
  subnet_id     = aws_subnet.public_subnets[0].id # Associate with the first public subnet - put this in private subnet?

  vpc_security_group_ids = [aws_security_group.allow_ssh_oracle.id]
  root_block_device {
    volume_size = 30  # Oracle XE needs at least 12GB, adding extra space
    volume_type = "gp3"
  }

  user_data_replace_on_change = true
  user_data = <<-EOF
    #!/bin/bash
    set -e

    echo "Starting script..." >> /var/log/script_debug.log

    # Prepare Oracle data directory
    mkdir -p /opt/oracle/oradata
    chmod -R 777 /opt/oracle/oradata

    echo "Oracle folder created. Installing updates..." >> /var/log/script_debug.log

    # Update system and install Docker
    dnf update -y
    dnf install -y docker

    echo "Docker installed. Starting docker..." >> /var/log/script_debug.log

    systemctl enable docker
    systemctl start docker

    echo "Docker started. Installing docker compose..." >> /var/log/script_debug.log

    # Install Docker Compose
    curl -L "https://github.com/docker/compose/releases/download/v2.20.3/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose

    echo "Docker compose installed. Generating docker-compose.yml file..." >> /var/log/script_debug.log

    # Create docker-compose.yml
    cat > /opt/oracle/docker-compose.yml <<'DOCKER_COMPOSE'
    version: '3'
    services:
      oracle-xe:
        image: container-registry.oracle.com/database/express:21.3.0-xe
        container_name: oracle-xe
        ports:
          - "1521:1521"
          - "5500:5500"
        environment:
          - ORACLE_PWD=Welcome1
          - ORACLE_CHARACTERSET=AL32UTF8
        volumes:
          - /opt/oracle/oradata:/opt/oracle/oradata
        restart: always
    DOCKER_COMPOSE

    echo "File generated. Starting docker compose environment..." >> /var/log/script_debug.log

    # Start Oracle container
    cd /opt/oracle && docker-compose up -d

    echo "Docker compose started. Waiting for healthy status..." >> /var/log/script_debug.log

    until [ "$(docker inspect -f '{{.State.Health.Status}}' oracle-xe 2>/dev/null)" == "healthy" ]; do
      sleep 10
    done

    echo "Oracle container healthy" >> /var/log/script_debug.log

    # Create setup-xstream.sh with proper variable expansion
    cat > /opt/oracle/setup-xstream.sh <<'SCRIPT_EOF'
    #!/bin/bash
    set -e
    log() { echo "[XSTREAM] $1"; }

    log "Enable GoldenGate replication"
    docker exec -i oracle-xe sqlplus /nolog <<SQL
    CONNECT sys/Welcome1 AS SYSDBA
    ALTER SYSTEM SET enable_goldengate_replication=TRUE SCOPE=BOTH;
    EXIT;
    SQL

    log "Enable ARCHIVELOG mode"
    docker exec -i oracle-xe sqlplus /nolog <<SQL
    CONNECT sys/Welcome1 AS SYSDBA
    SHUTDOWN IMMEDIATE;
    STARTUP MOUNT;
    ALTER DATABASE ARCHIVELOG;
    ALTER DATABASE OPEN;
    EXIT;
    SQL

    log "Enable Supplemental Logging"
    docker exec -i oracle-xe sqlplus /nolog <<SQL
    CONNECT sys/Welcome1 AS SYSDBA
    ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
    EXIT;
    SQL

    log "Create CDB XStream tablespaces"
    docker exec -i oracle-xe sqlplus /nolog <<SQL
    CONNECT sys/Welcome1 AS SYSDBA
    CREATE TABLESPACE xstream_adm_tbs DATAFILE '/opt/oracle/oradata/XE/xstream_adm_tbs.dbf' SIZE 25M AUTOEXTEND ON;
    CREATE TABLESPACE xstream_tbs DATAFILE '/opt/oracle/oradata/XE/xstream_tbs.dbf' SIZE 25M AUTOEXTEND ON;
    EXIT;
    SQL

    log "Create PDB tablespaces and sample user"
    docker exec -i oracle-xe sqlplus /nolog <<SQL
    CONNECT sys/Welcome1 AS SYSDBA
    ALTER SESSION SET CONTAINER=XEPDB1;

    CREATE TABLESPACE xstream_adm_tbs DATAFILE '/opt/oracle/oradata/XE/XEPDB1/xstream_adm_tbs.dbf' SIZE 25M AUTOEXTEND ON;
    CREATE TABLESPACE xstream_tbs DATAFILE '/opt/oracle/oradata/XE/XEPDB1/xstream_tbs.dbf' SIZE 25M AUTOEXTEND ON;
    EXIT;
    SQL

    docker exec -i oracle-xe sqlplus /nolog <<SQL
    CONNECT sys/Welcome1 AS SYSDBA
    ALTER SESSION SET CONTAINER = XEPDB1;
    GRANT CREATE SESSION, CREATE TABLE, CREATE SEQUENCE, CREATE TRIGGER TO c##cfltuser;
    GRANT UNLIMITED TABLESPACE TO c##cfltuser;
    ALTER USER c##cfltuser QUOTA UNLIMITED ON USERS;
    EXIT;
    SQL

    log "Create COMMON XStream user"
    docker exec -i oracle-xe sqlplus /nolog <<SQL
    CONNECT sys/Welcome1 AS SYSDBA
    CREATE USER c##cfltuser IDENTIFIED BY My_RandomPass192837465 DEFAULT TABLESPACE xstream_adm_tbs QUOTA UNLIMITED ON xstream_adm_tbs CONTAINER=ALL;

    GRANT CREATE SESSION, SET CONTAINER, SELECT_CATALOG_ROLE TO c##cfltuser CONTAINER=ALL;
    GRANT FLASHBACK ANY TABLE, SELECT ANY TABLE, LOCK ANY TABLE TO c##cfltuser CONTAINER=ALL;
    GRANT CREATE TABLE, CREATE SEQUENCE, CREATE TRIGGER TO c##cfltuser CONTAINER=ALL;
    GRANT UNLIMITED TABLESPACE TO C##CFLTUSER;
    ALTER USER C##CFLTUSER QUOTA UNLIMITED ON USERS;

    BEGIN
      DBMS_XSTREAM_AUTH.GRANT_ADMIN_PRIVILEGE(
        grantee => 'c##cfltuser',
        privilege_type => 'CAPTURE',
        grant_select_privileges => TRUE,
        container => 'ALL'
      );
    END;
    /
    EXIT;
    SQL

    log "Create Outbound Server"
    docker exec -i oracle-xe sqlplus /nolog <<SQL
    CONNECT sys/Welcome1 AS SYSDBA
    DECLARE
      tables DBMS_UTILITY.UNCL_ARRAY;
      schemas DBMS_UTILITY.UNCL_ARRAY;
    BEGIN
      tables(1) := 'C##CFLTUSER.EMPLOYEES';
      tables(2) := NULL;
      schemas(1) := 'C##CFLTUSER';
      schemas(2) := NULL;
      DBMS_XSTREAM_ADM.CREATE_OUTBOUND(
        server_name => 'XOUT',
        source_container_name => 'XEPDB1',
        table_names => tables,
        schema_names => schemas
      );
    END;
    /
    EXEC DBMS_XSTREAM_ADM.ALTER_OUTBOUND(server_name=>'XOUT', connect_user=>'c##cfltuser');
    EXIT;
    SQL

    log "[XSTREAM] XStream setup complete"

    SCRIPT_EOF

    chmod +x /opt/oracle/setup-xstream.sh
    bash /opt/oracle/setup-xstream.sh >>/var/log/script_debug.log 2>&1

    echo "[XSTREAM] Oracle XE with XStream configured successfully" >> /var/log/script_debug.log
  EOF

  tags = {
    Name        = "${var.prefix}-oracle-xe"
  }
}

output "oracle_vm_db_details" {
  value = {
    "private_ip": aws_instance.oracle_instance.private_ip
    "connection_string": "sqlplus system/${var.oracle_db_password}@${aws_instance.oracle_instance.private_ip}:1521/XEPDB1"
    "express_url": "https://${aws_instance.oracle_instance.private_ip}:5500/em"
  }
  sensitive = true
}

output "oracle_xstream_connector" {
  value = {
    database_hostname = aws_instance.oracle_instance.public_dns
    database_port = var.oracle_db_port
    database_username   = var.oracle_db_user
    database_password   = nonsensitive(var.oracle_db_password)
    pluggable_database  = var.oracle_pdb_name
    xstream_server_name = var.oracle_xtream_outbound_server_name
    table_inclusion_regex = var.oracle_db_table_include_list
  }
}
