========
Overview
========

SAND No: SAND2022-6304 O

The Feature-based Anomaly Detection System provides a means of detecting anomalies in video data.

The FADS has the specific advantage that it can run without a GPU in a reasonable time, without needing a training step, because it uses models pre-trained on generic image data.

https://arxiv.org/pdf/2204.10318.pdf

Installation
============

::

    pip install feature-anomaly-detection-system


Development
===========

To run all the tests run::

    tox

Note, to combine the coverage data from all the tox environments run:

.. list-table::
    :widths: 10 90
    :stub-columns: 1

    - - Windows
      - ::

            set PYTEST_ADDOPTS=--cov-append
            tox

    - - Other
      - ::

            PYTEST_ADDOPTS=--cov-append tox
