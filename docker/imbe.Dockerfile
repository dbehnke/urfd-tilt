FROM urfd-common

WORKDIR /build/imbe_vocoder
COPY . .

RUN make clean && make && (make install || true) \
    && cp libimbe_vocoder.a /usr/local/lib/ \
    && cp *.h /usr/local/include/
