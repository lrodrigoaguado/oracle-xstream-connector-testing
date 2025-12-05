############### Global Variables
variable "region" {
  description = "The region of Confluent Cloud Network"
  type        = string
  default     = "eu-west-1"
}

variable "prefix" {
  description = "Prefix used in all resources created"
  type        = string
  default     = "test-xstream-connector"
}

################ Confluent Cloud Variables
variable "confluent_cloud_api_key" {
  description = "Confluent Cloud API Key (also referred as Cloud API ID)."
  type        = string
}

variable "confluent_cloud_api_secret" {
  description = "Confluent Cloud API Secret."
  type        = string
  sensitive   = true
}

variable "use_existing_confluent_resources" {
  description = "Set to true to use existing Confluent Cloud environment and cluster."
  type        = bool
  default     = false
}

variable "confluent_environment_name" {
  description = "Name of the existing Confluent Cloud environment (required if use_existing_confluent_resources is true)."
  type        = string
  default     = null
}

variable "confluent_cluster_name" {
  description = "Name of the existing Confluent Cloud cluster (required if use_existing_confluent_resources is true)."
  type        = string
  default     = null
}


############### AWS Networking Variables
variable "vpc_cidr" {
  description = "VPC Cidr to be created"
  type        = string
  default     = "10.0.0.0/16"
}

########## Oracle DB Variables
variable "oracle_db_name" {
  description = "Oracle DB Name"
  type        = string
  default     = "XE"
}

variable "oracle_db_user" {
  description = "Oracle DB Username"
  type        = string
  default     = "c##cfltuser"
}

variable "oracle_db_password" {
  description = "Oracle DB Password"
  type        = string
  sensitive   = true
  default     = "My_RandomPass192837465"
}

variable "oracle_db_port" {
  description = "Oracle DB Port"
  type        = number
  default     = 1521
}

variable "oracle_pdb_name" {
  description = "Oracle DB Name"
  type        = string
  default     = "XEPDB1"
}

variable "oracle_db_table_include_list" {
  description = "Oracle tables include list for Oracle Xstream connector to stream"
  type        = string
  default     = "TESTING[.].*"
}

variable "oracle_xtream_outbound_server_name" {
  description = "Oracle Xstream outbound server name"
  type        = string
  default     = "XOUT"
}

resource "random_id" "env_display_id" {
    byte_length = 4
}
