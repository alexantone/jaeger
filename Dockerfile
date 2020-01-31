#   Copyright (c) 2020 ENEA
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.

#----------------------------------------------------------

FROM ubuntu:18.04 as builder

# ARG ARCH_VARIANT=amd64
ARG ARCH_VARIANT=arm64
ARG JAEGER_VER=v1.16.0

RUN apt-get update -y && apt-get install -y \
    autoconf \
    autoconf-archive \
    automake \
    autotools-dev \
    build-essential \
    g++  \
    gcc \
    git \
    libbz2-dev \
    libicu-dev \
    libsctp-dev \
    libtool \
    lksctp-tools \
    make \
    python-dev \
    pkg-config \
    software-properties-common \
    wget \
    zlib1g \
    zlib1g-dev \
    zlibc \
    zip



RUN wget -q https://dl.yarnpkg.com/debian/pubkey.gpg -O - | apt-key add - \
    && echo "deb https://dl.yarnpkg.com/debian/ stable main" > /etc/apt/sources.list.d/yarn.list \
    && apt remove cmdtest \
    && apt-get update -y && apt-get install -y yarn

# Install GO & dep
ENV GOLANG_VERSION=1.12.1
ENV GOLANG_PKG=go${GOLANG_VERSION}.linux-${ARCH_VARIANT}.tar.gz
ENV GOPATH=/go
ENV PATH="/usr/local/go/bin:${GOPATH}/bin:${PATH}"

RUN mkdir -p ${GOPATH}/bin
RUN wget -q https://dl.google.com/go/${GOLANG_PKG} \
    && tar xvzf ${GOLANG_PKG} -C /usr/local
RUN wget -q https://raw.githubusercontent.com/golang/dep/master/install.sh \
    && bash install.sh

# RUN go get -d -u github.com/golang/dep 
# RUN cd $(go env GOPATH)/src/github.com/golang/dep \
#     && DEP_LATEST=$(git describe --abbrev=0 --tags) \
#     && git checkout $DEP_LATEST \
#     && go install -ldflags="-X main.version=$DEP_LATEST" ./cmd/dep


ENV WORKDIR="$GOPATH/src/github.com/jaegertracing/jaeger"
RUN mkdir -p ${WORKDIR}
WORKDIR ${WORKDIR}

RUN git clone -b ${JAEGER_VER} https://github.com/jaegertracing/jaeger.git ./


RUN set -xv \
    && echo " ** WORKINGDIR: $(pwd)" && ls -la \
    && git submodule update --init --recursive \
    && { dep check ; dep ensure; } \
    && make install-tools

# RUN make test
RUN make --debug=vjm build-all-in-one-linux


# ------------------- Package ------------------------------------------
# Dumped from: ./jaeger/cmd/all-in-one/Dockerfile
FROM alpine:latest as certs
RUN apk add --update --no-cache ca-certificates

FROM scratch

ENV BUILD_DIR=/go/src/github.com/jaegertracing/jaeger

COPY --from=certs /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=builder ${BUILD_DIR}/cmd/all-in-one/all-in-one-linux /go/bin/
COPY --from=builder ${BUILD_DIR}/cmd/all-in-one/sampling_strategies.json /etc/jaeger/

# Agent zipkin.thrift compact
EXPOSE 5775/udp

# Agent jaeger.thrift compact
EXPOSE 6831/udp

# Agent jaeger.thrift binary
EXPOSE 6832/udp

# Agent config HTTP
EXPOSE 5778

# Collector HTTP
EXPOSE 14268

# Collector gRPC
EXPOSE 14250

# Web HTTP
EXPOSE 16686

ENTRYPOINT ["/go/bin/all-in-one-linux"]
CMD ["--sampling.strategies-file=/etc/jaeger/sampling_strategies.json"]
