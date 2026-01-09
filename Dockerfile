# syntax=docker/dockerfile:1
FROM golang AS build-stage

WORKDIR /build

# Layer 1: Copy dependency manifest files
# This layer is cached unless these files change
COPY go.mod go.sum Makefile Makefile.common ./

# Layer 2: Download Go modules
# This layer is cached unless go.mod or go.sum changes
RUN go mod download

# Layer 3: Install DB2 driver
# This is the expensive step that downloads from IBM
# Cached unless Makefile or go.mod changes
RUN make install-db2-driver

# Layer 4: Copy all source code
# This layer is invalidated whenever ANY source file changes
# setenv.sh is  excluded  via .dockerignore
COPY . .

# Layer 5: Build the exporter
# Only rebuilds when source code changes
RUN set -e ;\
    cat ./setenv.sh ;\
    . ./setenv.sh ;\
    make exporter

# TODO: Is the golang image really based on Debian?
# Final stage - minimal runtime image
FROM debian:13-slim AS final-stage

# Copy the DB2 CLI driver from build stage
COPY --from=build-stage /go/pkg/mod/github.com/ibmdb/ /go/pkg/mod/github.com/ibmdb/

# Copy the compiled binary
COPY --from=build-stage /build/bin/ibm_db2_exporter /usr/local/bin/ibm_db2_exporter

# Install runtime dependencies
RUN set -e ;\
    apt-get update ;\
    apt-get install -y --no-install-recommends libxml2 ;\
    rm -rf /var/lib/apt/lists/*

# Set environment variables for DB2 driver
ENV LD_LIBRARY_PATH=/go/pkg/mod/github.com/ibmdb/clidriver/lib/ \
    CGO_LDFLAGS=-L/go/pkg/mod/github.com/ibmdb/clidriver/lib/ \
    CGO_CFLAGS=-I/go/pkg/mod/github.com/ibmdb/clidriver/include/ \
    IBM_DB_HOME=/go/pkg/mod/github.com/ibmdb/clidriver

ENTRYPOINT ["/usr/local/bin/ibm_db2_exporter"]

# TODO: User?
# TODO: chmod / chown
