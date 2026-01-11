FROM urfd-common

WORKDIR /build/md380_vocoder_dynarmic
COPY . .

# Clean stale build artifacts
RUN rm -rf build && mkdir build
WORKDIR /build/md380_vocoder_dynarmic/build

# Build and install
RUN cmake .. && make && bash -x ../makelib.sh \
    && cp libmd380_vocoder.a /usr/local/lib/ \
    && cp ../md380_vocoder.h /usr/local/include/
