##= BUILDER =##
FROM 84codes/crystal:latest-debian-12 As builder

WORKDIR /cyclonedx-cr
COPY . .

RUN apt-get update && \
    apt-get install -y libyaml-dev && \
    shards install --production && \
    shards build --release --no-debug --production --static
# Ref: https://crystal-lang.org/reference/1.15/guides/static_linking.html

##= RUNNER =##
FROM debian:13-slim

COPY --from=builder /cyclonedx-cr/bin/cyclonedx-cr /usr/local/bin/cyclonedx-cr
USER 2:2

CMD ["cyclonedx-cr"]
