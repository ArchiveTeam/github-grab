FROM warcforceone/grab-base
COPY . /grab
RUN ln -fs /usr/local/bin/wget-lua /grab/wget-at
