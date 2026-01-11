FROM urfd-common

WORKDIR /build/urfd

# Copy source
COPY . /build/urfd

WORKDIR /build/urfd/reflector

# Create urfd.mk
RUN echo "DHT=false" > urfd.mk

# Build
RUN make clean && make

# Install binaries to /usr/local/bin for verify or easy usage, though we use them in docker-compose from build dir or copy?
# docker-compose uses 'urfd' image.
# We should probably set CMD or ENTRYPOINT or move binaries to a known path.
# In urfd-docker/Dockerfile:
# COPY ... /usr/local/bin
# CMD ["/bin/bash"]
# But docker-compose had: command: urfd
# So we need urfd in PATH.

RUN cp urfd /usr/local/bin/ && \
    cp inicheck /usr/local/bin/ && \
    cp dbutil /usr/local/bin/ && \
    cp ../radmin /usr/local/bin/
