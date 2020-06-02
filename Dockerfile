FROM tarantool/tarantool:2.x-centos7

WORKDIR /app

RUN yum install -y git \
                   cmake \
                   make \
                   gcc \
                   gobject-introspection-devel

RUN yum install -y https://apache.bintray.com/arrow/centos/$(cut -d: -f5 /etc/system-release-cpe)/apache-arrow-release-latest.rpm
RUN yum install -y --enablerepo=epel arrow-devel
RUN yum install -y --enablerepo=epel arrow-glib-devel

COPY . .
RUN tarantoolctl rocks make
RUN tarantoolctl rocks install icu-date
RUN mkdir -p tmp
RUN tarantoolctl rocks install --server=http://luarocks.org lgi
RUN tarantoolctl rocks install https://raw.githubusercontent.com/vasiliy-t/grafana-tarantool-datasource-backend/995982a5299db08191ec317f1098ca96d07878c0/grafana-tarantool-datasource-backend-scm-1.rockspec

CMD ["tarantool", "init.lua"]
