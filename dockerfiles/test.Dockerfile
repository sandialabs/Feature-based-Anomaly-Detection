ARG DOCKER_BASE_IMAGE_PREFIX
ARG DOCKER_BASE_IMAGE_NAMESPACE
ARG DOCKER_BASE_IMAGE_NAME=feature-anomaly-detection/requirements
ARG DOCKER_BASE_IMAGE_TAG=latest
FROM ${DOCKER_BASE_IMAGE_PREFIX}${DOCKER_BASE_IMAGE_NAMESPACE}/${DOCKER_BASE_IMAGE_NAME}:${DOCKER_BASE_IMAGE_TAG}

ARG ETC_ENVIRONMENT_LOCATION

COPY dockerfiles/before_script.sh .
# Depending on the base image used, we might lack wget/curl/etc to fetch environment.sh,
# but the Kaniko image must have successfully fetched it so we can just copy it.
ADD environment.sh .

# .dockerignore keeps .tox and so forth out of the COPY.
COPY . feature-anomaly-detection
# If we ran before_script in a separate RUN before the COPY of the code,
# then that layer could stay cached when the repo contents changed,
# but it's more valuable to keep all the environment variables confined to a single RUN.
# before_script.sh shouldn't take long to run anyway.

# The before_script.sh script sets several environment variables.
# Environment variables do *not* persist across Docker RUN lines.
# See also https://vsupalov.com/set-dynamic-environment-variable-during-docker-image-build/
# This allows Docker images to be portable to other networks if necessary.
RUN set -o allexport \
    && if [ -z ${FTP_PROXY+ABC} ]; then echo "FTP_PROXY is unset, so not doing any shenanigans."; . ./before_script.sh; else SSH_PRIVATE_DEPLOY_KEY="$FTP_PROXY" . ./before_script.sh; fi \
    && set +o allexport \
    # Unfortunately, the -e flag is not enabled on all platforms,
    # so we cannot guarantee that we will stop here if before_script.sh crashes.
    && wget http://www.google.com/index.html && echo "wget works" && rm index.html \
    && python -m pip install --no-cache-dir ./feature-anomaly-detection \
    && apt-get install --assume-yes libkrb5-dev \
    && python -m pip install --no-cache-dir git+https://github.com/jborean93/smbprotocol.git#egg=smbprotocol[kerberos] \
    && (ssh-add -D || echo "ssh-add -D failed, hopefully because we never installed openssh-client in the first place.")

RUN mkdir /video_files

# Ideally we want assembler.py to insert appropriate EXPOSE instructions for any ports,
# such as port 8888 for Jupyter or port 8050 for Plotly Dash.
# However, unless you're having containers talk to other containers,
# EXPOSE does not technically do anything you care about;
# docker run --publish does all the heavy lifting.
# https://www.ctl.io/developers/blog/post/docker-networking-rules
# https://we-are.bookmyshow.com/understanding-expose-in-dockerfile-266938b6a33d
# https://docs.docker.com/engine/reference/builder/#expose

EXPOSE 8888

# CMD ["python", "-m", "feature_anomaly_detection"]
ENTRYPOINT ["python", "-m", "jupyter", "lab", "--allow-root", "--ip", "0.0.0.0"]
