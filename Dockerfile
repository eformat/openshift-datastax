FROM datastax/dse-server:6.0.4
ENV DS_LICENSE=accept
COPY entrypoint.sh /
USER 999
EXPOSE 9042
