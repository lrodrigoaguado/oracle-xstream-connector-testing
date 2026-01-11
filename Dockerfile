FROM confluentinc/cp-server-connect:7.9.5
USER root

ARG LIBAIO_RPM
ARG INSTANT_CLIENT_RPM

COPY etc/${LIBAIO_RPM} etc/${INSTANT_CLIENT_RPM} /tmp/

RUN yum install -y /tmp/${LIBAIO_RPM}
RUN yum install -y /tmp/${INSTANT_CLIENT_RPM}
USER appuser
