from debian:buster

RUN apt-get update && apt-get install -y \
	ca-certificates \
        bzip2 \
        curl \
        wget \
        parallel \
	--no-install-recommends \
	&& rm -rf /var/lib/apt/lists/*

COPY parse_enclosure.xsl /mashpodder/
COPY mashpodder.sh /mashpodder/
COPY docker-entrypoint.sh /mashpodder/
COPY mp.conf /mashpodder/
WORKDIR /mashpodder
ENTRYPOINT [ "./docker-entrypoint.sh" ]
