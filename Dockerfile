FROM alpine:3.18

RUN apk update && apk add --no-cache \
    build-base \
    git \
    curl \
    jq \
    dos2unix \
    bash \
    linux-headers

# Сборка 3proxy
RUN git clone --branch 0.9.4 --depth 1 https://github.com/z3APA3A/3proxy.git /3proxy \
 && cd /3proxy \
 && make -f Makefile.Linux \
 && mkdir -p /usr/local/3proxy/bin /usr/local/3proxy/logs \
 && cp bin/3proxy /usr/local/3proxy/bin/ \
 && rm -rf /3proxy

COPY entrypoint.sh /entrypoint.sh
RUN dos2unix /entrypoint.sh && chmod +x /entrypoint.sh

ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
