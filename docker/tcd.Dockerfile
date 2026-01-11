FROM urfd-common

# Copy artifacts from libraries
COPY --from=imbe-lib /usr/local/lib/libimbe_vocoder.a /usr/local/lib/
COPY --from=imbe-lib /usr/local/include/*.h /usr/local/include/
COPY --from=md380-lib /usr/local/lib/libmd380_vocoder.a /usr/local/lib/
COPY --from=md380-lib /usr/local/include/md380_vocoder.h /usr/local/include/

WORKDIR /build

# Copy sources (Context MUST be parent directory 'urfd-dev')
COPY urfd /build/urfd
COPY tcd /build/tcd

WORKDIR /build/tcd

# Create tcd.mk
RUN echo "swambe2=true" > tcd.mk && \
    echo "swmodes=true" >> tcd.mk && \
    echo "debug=false" >> tcd.mk

# Fix Makefile link flags
RUN sed -i 's/-lmd380_vocoder/-lmd380_vocoder -lfmt/g' Makefile

# Build
RUN make clean && make swmodes=true

# Install
RUN cp tcd /usr/local/bin/

# Default command
CMD ["tcd"]
