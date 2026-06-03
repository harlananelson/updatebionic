FROM ubuntu:18.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    gfortran \
    libgdal-dev \
    libgeos-dev \
    libproj-dev \
    libudunits2-dev \
    libfreetype6-dev \
    libpng-dev \
    vim \
    openssh-client \
    curl \
    wget \
    ca-certificates \
    git \
    sudo \
    python3 \
    python3-pip \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

# Common locations in these setups
RUN mkdir -p /opt /tmp /home/jovyan /work

# We will install the "old" conda the way these containers usually get it.
# The exact bootstrap varies; the capture will tell us the resulting python version.
# A typical old bootstrap for these environments is something like the
# Anaconda/Miniconda installer that was current ~2019-2020, resulting in
# Python 3.7 + conda 4.7-ish.
#
# Here we use a known historical Miniconda3 that gives py 3.7 on glibc 2.27.
# If the capture shows a different exact python, we can adjust later.
RUN wget -q https://repo.anaconda.com/miniconda/Miniconda3-4.7.12-Linux-x86_64.sh -O /tmp/miniconda.sh || \
    wget -q https://repo.anaconda.com/miniconda/Miniconda3-py37_4.10.3-Linux-x86_64.sh -O /tmp/miniconda.sh
RUN bash /tmp/miniconda.sh -b -p /opt/conda && rm /tmp/miniconda.sh
ENV PATH="/opt/conda/bin:${PATH}"

# At this point the container has a /opt/conda that is "the old one".
# In real life the pyspark 2.4.4 is often provided by the platform via
# /usr/local/spark/python rather than (or in addition to) conda.
# We install a compatible old pyspark here for basic testing.
RUN /opt/conda/bin/pip install 'pyspark==2.4.4' 'pandas==0.25.3' --no-deps || true

# Also install a few things the user mentioned they add (plotnine etc.)
# into a clone later; for now just have them available in base for smoke tests.
RUN /opt/conda/bin/pip install plotnine lifelines || true

# Create a non-root user that will run the setup (simulating the real user).
ARG USERNAME=testuser
ARG USERID=1000
RUN useradd -m -u ${USERID} -s /bin/bash ${USERNAME} && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER ${USERNAME}
WORKDIR /home/${USERNAME}

# The setup scripts will be copied in at runtime from the mounted /host-updatebionic
# (so we always test the live versions on the host, not a stale baked copy).
# The driver scripts (the verifier + seeder) are baked at image build time from
# the context so `bash /run-test-inside.sh` works without extra mounts for the scripts themselves.
COPY run-test-inside.sh /run-test-inside.sh
COPY seed-from-captured-packs.sh /seed-from-captured-packs.sh
RUN chmod +x /run-test-inside.sh /seed-from-captured-packs.sh || true

# Also make the capture dir available inside at /capture (we will volume-mount it at run).
# (The COPY below is a no-op placeholder; the real content comes from the -v at `docker run`.)
# We just ensure the path exists for the inside script.
RUN mkdir -p /capture /capture-packs /host-updatebionic
