####################################
#   Multi-stage build
#       1. build tez
#       2. build hive base
####################################

# Stage 1 - Build Tez

FROM maven:3-jdk-8 as tez-builder

ARG TEZ_VERSION=0.9.2
ARG HADOOP_VERSION=3.1.4
ARG PROTOBUF_VERSION=2.5.0

RUN apt-get update && apt-get install -y autoconf automake libtool curl make g++ unzip

RUN curl -fSL "https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOBUF_VERSION}/protobuf-${PROTOBUF_VERSION}.tar.gz" --output protobuf-${PROTOBUF_VERSION}.tar.gz

# from https://github.com/protocolbuffers/protobuf/tree/v2.5.0
RUN tar -xvf protobuf-${PROTOBUF_VERSION}.tar.gz \
    && cd protobuf-${PROTOBUF_VERSION} \
    && ./configure --prefix=/usr \
    && make \
    && make check \
    && make install \
    && ldconfig

RUN git clone https://github.com/apache/tez.git /opt/tez

# the tez-ui code relies on very old versions of node, bower, yarn, etc.  i could never get it to build succesfully in docker therefore i skip it during build

RUN cd /opt/tez \
    && git checkout tags/rel/release-${TEZ_VERSION} -b release-${TEZ_VERSION} \
    && mvn clean package -Phadoop28 -Dhadoop.version=${HADOOP_VERSION} -Dprotobuf.version=${PROTOBUF_VERSION} -DskipTests=true -Dmaven.javadoc.skip=true --projects "!tez-ui" \
    && mkdir -pv /tmp/tez \
    && tar -xvf /opt/tez/tez-dist/target/tez-${TEZ_VERSION}-minimal.tar.gz -C /tmp/tez



# Stage 2 - Build Hive base

FROM timveil/docker-hadoop-core:3.1.x

LABEL maintainer="tjveil@gmail.com"

ENV HIVE_HOME=/opt/hive
ENV PATH=$HIVE_HOME/bin:$PATH
ENV HIVE_CONF_DIR=$HIVE_HOME/conf
ENV TEZ_CONF_DIR=/etc/tez/conf
ENV TEZ_LIB_DIR=/opt/tez

ARG HIVE_VERSION=3.1.2
ARG HIVE_DOWNLOAD_DIR=/tmp/hive
ARG POSTGRESQL_JDBC_VERSION=42.2.14

# removing older guava version which is causing classpath issues at runtime

# Install Hive and PostgreSQL JDBC
RUN curl -fSL https://archive.apache.org/dist/hive/hive-$HIVE_VERSION/apache-hive-$HIVE_VERSION-bin.tar.gz -o /tmp/hive.tar.gz \
    && mkdir -pv $HIVE_DOWNLOAD_DIR \
    && mkdir -pv $TEZ_CONF_DIR \
    && mkdir -pv $TEZ_LIB_DIR \
    && tar -xvf /tmp/hive.tar.gz -C $HIVE_DOWNLOAD_DIR --strip-components=1 \
    && mv -v $HIVE_DOWNLOAD_DIR /opt \
    && rm -rfv /tmp/hive.tar.gz \
    && rm -rfv $HIVE_HOME/lib/guava-*.jar \
    && cp $HADOOP_HOME/share/hadoop/common/lib/guava-*.jar $HIVE_HOME/lib/ \
    && rm -rfv $HIVE_HOME/lib/postgresql-*.jre*.jar \
    && curl -fSL https://jdbc.postgresql.org/download/postgresql-$POSTGRESQL_JDBC_VERSION.jar -o $HIVE_HOME/lib/postgresql-jdbc.jar

COPY --from=tez-builder /tmp/tez/*.jar $TEZ_LIB_DIR/

# Custom configuration goes here
ADD conf/hive-site.xml $HIVE_CONF_DIR
ADD conf/metastore-site.xml $HIVE_CONF_DIR
ADD conf/metastore-log4j2.properties $HIVE_CONF_DIR
ADD conf/beeline-log4j2.properties $HIVE_CONF_DIR
ADD conf/hive-exec-log4j2.properties $HIVE_CONF_DIR
ADD conf/hive-log4j2.properties $HIVE_CONF_DIR
ADD conf/llap-daemon-log4j2.properties $HIVE_CONF_DIR
ADD conf/llap-cli-log4j2.properties $HIVE_CONF_DIR
ADD conf/tez-site.xml $TEZ_CONF_DIR

EXPOSE 10000

# hive ui
EXPOSE 10002