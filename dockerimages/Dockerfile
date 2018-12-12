FROM centos:7

RUN yum install -y epel-release; \
    yum install -y redis nc bind-utils && \
    yum clean all && \
    rm -rf /var/cache/yum

RUN mkdir -p /opt/redis-sentinel
WORKDIR /opt/redis-sentinel
ENV REDIS_SENTINEL_HOME /opt/redis-sentinel

COPY fix-permissions.sh fix-permissions.sh
COPY redis-master.conf redis-master/redis.conf
COPY redis-slave.conf redis-slave/redis.conf
COPY run.sh run.sh

RUN chmod +x fix-permissions.sh

RUN ./fix-permissions.sh /var/lib/redis
RUN ./fix-permissions.sh /etc
RUN ./fix-permissions.sh /opt/redis-sentinel


ENTRYPOINT [ "bash", "-c" ]
CMD [ "./run.sh" ]
