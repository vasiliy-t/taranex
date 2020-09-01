FROM tarantool/tarantool:2.x-centos7

WORKDIR /app

RUN yum install -y git \
                   cmake \
                   make \
                   gcc

CMD ["tarantoolctl", "rocks", "install", "luatest"]
