FROM confluentinc/cp-server-connect:7.9.5
USER root

COPY etc/libaio-0.3.112-1.el8.aarch64.rpm etc/oracle-instantclient-basic-23.26.0.0.0-1.el8.aarch64.rpm /tmp/

RUN yum install -y /tmp/libaio-0.3.112-1.el8.aarch64.rpm
RUN yum install -y /tmp/oracle-instantclient-basic-23.26.0.0.0-1.el8.aarch64.rpm
USER appuser
