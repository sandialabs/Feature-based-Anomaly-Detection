ARG DOCKER_BASE_IMAGE_PREFIX
ARG DOCKER_BASE_IMAGE_NAMESPACE
ARG DOCKER_BASE_IMAGE_NAME
ARG DOCKER_BASE_IMAGE_TAG
FROM ${DOCKER_BASE_IMAGE_PREFIX}${DOCKER_BASE_IMAGE_NAMESPACE}/${DOCKER_BASE_IMAGE_NAME}:${DOCKER_BASE_IMAGE_TAG}
#FROM pytorch/pytorch

ARG FIX_ALL_GOTCHAS_SCRIPT_LOCATION
ARG ETC_ENVIRONMENT_LOCATION
ARG CLEANUP_SCRIPT_LOCATION

# Depending on the base image used, we might lack wget/curl/etc to fetch ETC_ENVIRONMENT_LOCATION.
COPY environment.sh ./environment.sh
ADD $FIX_ALL_GOTCHAS_SCRIPT_LOCATION .
ADD $CLEANUP_SCRIPT_LOCATION .

RUN set -o allexport \
    && . ./fix_all_gotchas.sh \
    && set +o allexport \
    # && conda install --channel conda-forge numpy pillow matplotlib scikit-learn pyyaml pytorch torchvision typing-extensions \
    && python -m pip install jupyterlab jupytext jupyter-autotime nbconvert ipykernel numpy pandas pillow matplotlib scikit-learn pyyaml torch torchvision pytorchvideo typing-extensions \
    && python -m ipykernel install \
    && . ./cleanup.sh
