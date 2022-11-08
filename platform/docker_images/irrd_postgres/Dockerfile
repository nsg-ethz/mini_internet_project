FROM postgres

ENV POSTGRES_USER='irrd'
ENV POSTGRES_PASSWORD='irrd'
EXPOSE 5432

COPY init-user-db.sh /docker-entrypoint-initdb.d/init-user-db.sh
COPY postgresql.conf /etc/postgresql/postgresql.conf
